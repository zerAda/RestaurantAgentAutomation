-- =============================================================================
-- Migration: P1-PAY-01 - Paiements Algérie (COD + Acompte + CIB/Edahabia)
-- Date: 2026-01-23
-- Ticket: P1-PAY-01
-- 
-- Purpose:
-- 1. Payment intents with state machine
-- 2. COD (Cash on Delivery) support
-- 3. Optional deposit (acompte) for delivery orders
-- 4. Preparation for CIB/Edahabia integration
-- 5. Anti-fraud: soft blacklist + thresholds
-- =============================================================================

BEGIN;

-- =============================================================================
-- 1. Payment methods enum
-- =============================================================================
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'payment_method_enum') THEN
        CREATE TYPE payment_method_enum AS ENUM (
            'COD',           -- Cash on Delivery
            'DEPOSIT_COD',   -- Partial deposit + COD for rest
            'CIB',           -- Carte CIB (future)
            'EDAHABIA',      -- Carte Edahabia (future)
            'BARIDIMOB',     -- BaridiMob (future)
            'FREE'           -- No payment (promo/test)
        );
    END IF;
END $$;

-- =============================================================================
-- 2. Payment status enum
-- =============================================================================
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'payment_status_enum') THEN
        CREATE TYPE payment_status_enum AS ENUM (
            'PENDING',           -- Awaiting action
            'DEPOSIT_REQUESTED', -- Deposit link sent
            'DEPOSIT_PAID',      -- Deposit received
            'CONFIRMED',         -- Payment confirmed (full or deposit ok for COD)
            'COLLECTED',         -- COD collected at delivery
            'COMPLETED',         -- Fully paid
            'FAILED',            -- Payment failed
            'REFUNDED',          -- Refunded
            'CANCELLED'          -- Cancelled
        );
    END IF;
END $$;

-- =============================================================================
-- 3. Payment intents table
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.payment_intents (
    id                  BIGSERIAL PRIMARY KEY,
    intent_id           UUID NOT NULL DEFAULT gen_random_uuid() UNIQUE,
    
    -- Context
    tenant_id           UUID NOT NULL,
    restaurant_id       UUID NOT NULL,
    order_id            UUID REFERENCES public.orders(order_id),
    conversation_key    TEXT NOT NULL,
    user_id             TEXT NOT NULL,
    
    -- Payment details
    method              payment_method_enum NOT NULL DEFAULT 'COD',
    status              payment_status_enum NOT NULL DEFAULT 'PENDING',
    
    -- Amounts (in centimes DZD)
    total_amount        INTEGER NOT NULL CHECK (total_amount >= 0),
    deposit_amount      INTEGER NOT NULL DEFAULT 0 CHECK (deposit_amount >= 0),
    deposit_paid        INTEGER NOT NULL DEFAULT 0 CHECK (deposit_paid >= 0),
    cod_amount          INTEGER NOT NULL DEFAULT 0 CHECK (cod_amount >= 0),
    cod_collected       INTEGER NOT NULL DEFAULT 0 CHECK (cod_collected >= 0),
    
    -- External payment reference (for CIB/Edahabia)
    external_ref        TEXT,
    external_provider   TEXT,
    
    -- Timestamps
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    confirmed_at        TIMESTAMPTZ,
    completed_at        TIMESTAMPTZ,
    expires_at          TIMESTAMPTZ,
    
    -- Metadata
    metadata_json       JSONB NOT NULL DEFAULT '{}'::jsonb
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_payment_intents_order 
    ON public.payment_intents(order_id);

CREATE INDEX IF NOT EXISTS idx_payment_intents_conversation 
    ON public.payment_intents(conversation_key);

CREATE INDEX IF NOT EXISTS idx_payment_intents_status 
    ON public.payment_intents(status) 
    WHERE status IN ('PENDING', 'DEPOSIT_REQUESTED');

CREATE INDEX IF NOT EXISTS idx_payment_intents_user 
    ON public.payment_intents(user_id, created_at DESC);

-- =============================================================================
-- 4. Payment history (audit trail)
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.payment_history (
    id                  BIGSERIAL PRIMARY KEY,
    payment_intent_id   BIGINT NOT NULL REFERENCES public.payment_intents(id),
    
    -- State change
    from_status         payment_status_enum,
    to_status           payment_status_enum NOT NULL,
    
    -- Details
    amount              INTEGER,
    actor               TEXT,  -- 'system', 'user', 'driver', 'admin'
    reason              TEXT,
    
    -- Timestamps
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    
    -- Metadata
    metadata_json       JSONB NOT NULL DEFAULT '{}'::jsonb
);

CREATE INDEX IF NOT EXISTS idx_payment_history_intent 
    ON public.payment_history(payment_intent_id, created_at DESC);

-- =============================================================================
-- 5. Customer payment profiles (for fraud/trust)
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.customer_payment_profiles (
    id                  BIGSERIAL PRIMARY KEY,
    user_id             TEXT NOT NULL UNIQUE,
    tenant_id           UUID NOT NULL,
    
    -- Stats
    total_orders        INTEGER NOT NULL DEFAULT 0,
    completed_orders    INTEGER NOT NULL DEFAULT 0,
    cancelled_orders    INTEGER NOT NULL DEFAULT 0,
    no_show_count       INTEGER NOT NULL DEFAULT 0,
    
    -- Trust score (0-100)
    trust_score         INTEGER NOT NULL DEFAULT 50 CHECK (trust_score BETWEEN 0 AND 100),
    
    -- Flags
    requires_deposit    BOOLEAN NOT NULL DEFAULT false,
    soft_blacklisted    BOOLEAN NOT NULL DEFAULT false,
    blacklist_reason    TEXT,
    blacklist_until     TIMESTAMPTZ,
    
    -- Timestamps
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_customer_payment_profiles_user 
    ON public.customer_payment_profiles(user_id);

CREATE INDEX IF NOT EXISTS idx_customer_payment_profiles_blacklist 
    ON public.customer_payment_profiles(soft_blacklisted) 
    WHERE soft_blacklisted = true;

-- =============================================================================
-- 6. Payment configuration per restaurant
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.restaurant_payment_config (
    id                  BIGSERIAL PRIMARY KEY,
    restaurant_id       UUID NOT NULL UNIQUE,
    
    -- Enabled methods
    cod_enabled         BOOLEAN NOT NULL DEFAULT true,
    deposit_enabled     BOOLEAN NOT NULL DEFAULT false,
    cib_enabled         BOOLEAN NOT NULL DEFAULT false,
    edahabia_enabled    BOOLEAN NOT NULL DEFAULT false,
    
    -- COD settings
    cod_max_amount      INTEGER NOT NULL DEFAULT 1000000,  -- 10,000 DZD default max
    
    -- Deposit settings (percentage or fixed)
    deposit_mode        TEXT NOT NULL DEFAULT 'PERCENTAGE' CHECK (deposit_mode IN ('PERCENTAGE', 'FIXED')),
    deposit_percentage  INTEGER NOT NULL DEFAULT 30 CHECK (deposit_percentage BETWEEN 0 AND 100),
    deposit_fixed       INTEGER NOT NULL DEFAULT 0,
    deposit_threshold   INTEGER NOT NULL DEFAULT 300000,  -- Only require deposit above this (3000 DZD)
    
    -- Trust thresholds
    no_deposit_min_orders   INTEGER NOT NULL DEFAULT 3,   -- No deposit after N successful orders
    no_deposit_min_score    INTEGER NOT NULL DEFAULT 70,  -- No deposit if trust score >= this
    
    -- External integration (future)
    cib_merchant_id     TEXT,
    edahabia_merchant_id TEXT,
    
    -- Timestamps
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- =============================================================================
-- 7. Helper functions
-- =============================================================================

-- Calculate deposit amount for an order
CREATE OR REPLACE FUNCTION public.calculate_deposit(
    p_restaurant_id UUID,
    p_user_id TEXT,
    p_total_amount INTEGER
)
RETURNS TABLE(
    deposit_required BOOLEAN,
    deposit_amount INTEGER,
    reason TEXT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_config RECORD;
    v_profile RECORD;
    v_deposit INTEGER := 0;
BEGIN
    -- Get restaurant config
    SELECT * INTO v_config
    FROM public.restaurant_payment_config
    WHERE restaurant_id = p_restaurant_id;
    
    -- Default config if not exists
    IF NOT FOUND THEN
        v_config := ROW(
            null, p_restaurant_id, true, false, false, false,
            1000000, 'PERCENTAGE', 30, 0, 300000, 3, 70,
            null, null, now(), now()
        );
    END IF;
    
    -- Deposit not enabled
    IF NOT v_config.deposit_enabled THEN
        RETURN QUERY SELECT false, 0, 'deposit_disabled';
        RETURN;
    END IF;
    
    -- Below threshold
    IF p_total_amount < v_config.deposit_threshold THEN
        RETURN QUERY SELECT false, 0, 'below_threshold';
        RETURN;
    END IF;
    
    -- Check customer profile
    SELECT * INTO v_profile
    FROM public.customer_payment_profiles
    WHERE user_id = p_user_id;
    
    IF FOUND THEN
        -- Trusted customer exemption
        IF v_profile.completed_orders >= v_config.no_deposit_min_orders 
           AND v_profile.trust_score >= v_config.no_deposit_min_score
           AND NOT v_profile.requires_deposit THEN
            RETURN QUERY SELECT false, 0, 'trusted_customer';
            RETURN;
        END IF;
        
        -- Blacklisted
        IF v_profile.soft_blacklisted AND (v_profile.blacklist_until IS NULL OR v_profile.blacklist_until > NOW()) THEN
            -- Require full prepayment for blacklisted
            RETURN QUERY SELECT true, p_total_amount, 'blacklisted';
            RETURN;
        END IF;
    END IF;
    
    -- Calculate deposit
    IF v_config.deposit_mode = 'PERCENTAGE' THEN
        v_deposit := (p_total_amount * v_config.deposit_percentage / 100);
    ELSE
        v_deposit := v_config.deposit_fixed;
    END IF;
    
    -- Ensure deposit doesn't exceed total
    v_deposit := LEAST(v_deposit, p_total_amount);
    
    RETURN QUERY SELECT true, v_deposit, 'standard_deposit';
END;
$$;

-- Create payment intent for order
CREATE OR REPLACE FUNCTION public.create_payment_intent(
    p_tenant_id UUID,
    p_restaurant_id UUID,
    p_order_id UUID,
    p_conversation_key TEXT,
    p_user_id TEXT,
    p_total_amount INTEGER,
    p_method payment_method_enum DEFAULT 'COD'
)
RETURNS TABLE(
    intent_id UUID,
    method payment_method_enum,
    total_amount INTEGER,
    deposit_required BOOLEAN,
    deposit_amount INTEGER,
    cod_amount INTEGER
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_intent_id UUID;
    v_deposit_required BOOLEAN;
    v_deposit_amount INTEGER;
    v_deposit_reason TEXT;
    v_cod_amount INTEGER;
    v_status payment_status_enum;
BEGIN
    -- Calculate deposit if method is COD or DEPOSIT_COD
    IF p_method IN ('COD', 'DEPOSIT_COD') THEN
        SELECT dr.deposit_required, dr.deposit_amount, dr.reason
        INTO v_deposit_required, v_deposit_amount, v_deposit_reason
        FROM public.calculate_deposit(p_restaurant_id, p_user_id, p_total_amount) dr;
    ELSE
        v_deposit_required := false;
        v_deposit_amount := 0;
    END IF;
    
    -- Adjust method based on deposit
    IF v_deposit_required AND v_deposit_amount > 0 THEN
        p_method := 'DEPOSIT_COD';
        v_cod_amount := p_total_amount - v_deposit_amount;
        v_status := 'PENDING';
    ELSE
        v_deposit_amount := 0;
        v_cod_amount := p_total_amount;
        v_status := 'CONFIRMED';  -- COD without deposit is auto-confirmed
    END IF;
    
    -- Insert payment intent
    INSERT INTO public.payment_intents (
        tenant_id, restaurant_id, order_id, conversation_key, user_id,
        method, status, total_amount, deposit_amount, cod_amount,
        expires_at
    ) VALUES (
        p_tenant_id, p_restaurant_id, p_order_id, p_conversation_key, p_user_id,
        p_method, v_status, p_total_amount, v_deposit_amount, v_cod_amount,
        CASE WHEN v_deposit_required THEN NOW() + INTERVAL '30 minutes' ELSE NULL END
    )
    RETURNING payment_intents.intent_id INTO v_intent_id;
    
    -- Log history
    INSERT INTO public.payment_history (payment_intent_id, to_status, actor, reason)
    SELECT pi.id, v_status, 'system', v_deposit_reason
    FROM public.payment_intents pi
    WHERE pi.intent_id = v_intent_id;
    
    RETURN QUERY
    SELECT v_intent_id, p_method, p_total_amount, v_deposit_required, v_deposit_amount, v_cod_amount;
END;
$$;

-- Confirm deposit payment
CREATE OR REPLACE FUNCTION public.confirm_deposit_payment(
    p_intent_id UUID,
    p_amount INTEGER,
    p_external_ref TEXT DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
DECLARE
    v_intent RECORD;
BEGIN
    SELECT * INTO v_intent
    FROM public.payment_intents
    WHERE intent_id = p_intent_id
    FOR UPDATE;
    
    IF NOT FOUND OR v_intent.status NOT IN ('PENDING', 'DEPOSIT_REQUESTED') THEN
        RETURN false;
    END IF;
    
    -- Validate amount
    IF p_amount < v_intent.deposit_amount THEN
        RETURN false;
    END IF;
    
    -- Update intent
    UPDATE public.payment_intents
    SET status = 'DEPOSIT_PAID',
        deposit_paid = p_amount,
        external_ref = COALESCE(p_external_ref, external_ref),
        updated_at = NOW(),
        confirmed_at = NOW()
    WHERE intent_id = p_intent_id;
    
    -- Log history
    INSERT INTO public.payment_history (payment_intent_id, from_status, to_status, amount, actor, reason)
    SELECT pi.id, v_intent.status, 'DEPOSIT_PAID', p_amount, 'system', 'deposit_confirmed'
    FROM public.payment_intents pi
    WHERE pi.intent_id = p_intent_id;
    
    -- Confirm the related order if exists
    IF v_intent.order_id IS NOT NULL THEN
        UPDATE public.orders
        SET status = 'CONFIRMED',
            updated_at = NOW()
        WHERE order_id = v_intent.order_id
          AND status IN ('NEW','ACCEPTED');
    END IF;
    
    RETURN true;
END;
$$;

-- Mark COD collected
CREATE OR REPLACE FUNCTION public.collect_cod_payment(
    p_intent_id UUID,
    p_amount INTEGER,
    p_actor TEXT DEFAULT 'driver'
)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
DECLARE
    v_intent RECORD;
BEGIN
    SELECT * INTO v_intent
    FROM public.payment_intents
    WHERE intent_id = p_intent_id
    FOR UPDATE;
    
    IF NOT FOUND OR v_intent.status NOT IN ('CONFIRMED', 'DEPOSIT_PAID') THEN
        RETURN false;
    END IF;
    
    -- Update intent
    UPDATE public.payment_intents
    SET status = 'COLLECTED',
        cod_collected = p_amount,
        updated_at = NOW()
    WHERE intent_id = p_intent_id;
    
    -- Log history
    INSERT INTO public.payment_history (payment_intent_id, from_status, to_status, amount, actor, reason)
    SELECT pi.id, v_intent.status, 'COLLECTED', p_amount, p_actor, 'cod_collected'
    FROM public.payment_intents pi
    WHERE pi.intent_id = p_intent_id;
    
    -- Mark order as delivered
    IF v_intent.order_id IS NOT NULL THEN
        UPDATE public.orders
        SET status = 'DONE',
            updated_at = NOW()
        WHERE order_id = v_intent.order_id;
    END IF;
    
    RETURN true;
END;
$$;

-- Update customer profile after order completion
CREATE OR REPLACE FUNCTION public.update_customer_payment_profile(
    p_user_id TEXT,
    p_tenant_id UUID,
    p_completed BOOLEAN,
    p_no_show BOOLEAN DEFAULT false
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    v_score_delta INTEGER := 0;
BEGIN
    -- Ensure profile exists
    INSERT INTO public.customer_payment_profiles (user_id, tenant_id)
    VALUES (p_user_id, p_tenant_id)
    ON CONFLICT (user_id) DO NOTHING;
    
    -- Calculate score change
    IF p_completed THEN
        v_score_delta := 5;  -- +5 for completed order
    ELSIF p_no_show THEN
        v_score_delta := -20;  -- -20 for no-show
    ELSE
        v_score_delta := -5;  -- -5 for cancellation
    END IF;
    
    -- Update profile
    UPDATE public.customer_payment_profiles
    SET total_orders = total_orders + 1,
        completed_orders = completed_orders + CASE WHEN p_completed THEN 1 ELSE 0 END,
        cancelled_orders = cancelled_orders + CASE WHEN NOT p_completed AND NOT p_no_show THEN 1 ELSE 0 END,
        no_show_count = no_show_count + CASE WHEN p_no_show THEN 1 ELSE 0 END,
        trust_score = GREATEST(0, LEAST(100, trust_score + v_score_delta)),
        requires_deposit = CASE 
            WHEN p_no_show THEN true 
            WHEN no_show_count >= 2 THEN true
            ELSE requires_deposit 
        END,
        soft_blacklisted = CASE
            WHEN p_no_show AND no_show_count >= 2 THEN true
            ELSE soft_blacklisted
        END,
        blacklist_reason = CASE
            WHEN p_no_show AND no_show_count >= 2 THEN 'repeated_no_show'
            ELSE blacklist_reason
        END,
        blacklist_until = CASE
            WHEN p_no_show AND no_show_count >= 2 THEN NOW() + INTERVAL '30 days'
            ELSE blacklist_until
        END,
        updated_at = NOW()
    WHERE user_id = p_user_id;
END;
$$;

-- =============================================================================
-- 8. Message templates for payments (FR/AR)
-- =============================================================================
INSERT INTO public.message_templates(template_key, locale, content, variables, tenant_id)
VALUES
    -- Deposit request
    ('PAYMENT_DEPOSIT_REQUIRED','fr','💳 Un acompte de {{amount}} DA est requis pour confirmer ta commande. Tu peux payer par:\n• BaridiMob: {{baridimob_code}}\n• Virement: voir détails ci-dessous\n\nDélai: {{minutes}} min','["amount","baridimob_code","minutes"]'::jsonb,'_GLOBAL'),
    ('PAYMENT_DEPOSIT_REQUIRED','ar','💳 يجب دفع عربون {{amount}} دج لتأكيد طلبك. يمكنك الدفع عبر:\n• بريديموب: {{baridimob_code}}\n• تحويل: انظر التفاصيل\n\nالمهلة: {{minutes}} دقيقة','["amount","baridimob_code","minutes"]'::jsonb,'_GLOBAL'),
    
    -- Deposit confirmed
    ('PAYMENT_DEPOSIT_CONFIRMED','fr','✅ Acompte de {{amount}} DA reçu! Ta commande est confirmée. Reste à payer à la livraison: {{remaining}} DA','["amount","remaining"]'::jsonb,'_GLOBAL'),
    ('PAYMENT_DEPOSIT_CONFIRMED','ar','✅ تم استلام العربون {{amount}} دج! طلبك مؤكد. المتبقي عند التسليم: {{remaining}} دج','["amount","remaining"]'::jsonb,'_GLOBAL'),
    
    -- COD info
    ('PAYMENT_COD_INFO','fr','💵 Paiement à la livraison: {{amount}} DA. Prépare la somme exacte si possible!','["amount"]'::jsonb,'_GLOBAL'),
    ('PAYMENT_COD_INFO','ar','💵 الدفع عند الاستلام: {{amount}} دج. جهز المبلغ بالضبط إن أمكن!','["amount"]'::jsonb,'_GLOBAL'),
    
    -- Payment expired
    ('PAYMENT_EXPIRED','fr','⏰ Délai de paiement dépassé. Ta commande a été annulée. Tu peux recommencer.','[]'::jsonb,'_GLOBAL'),
    ('PAYMENT_EXPIRED','ar','⏰ انتهت مهلة الدفع. تم إلغاء طلبك. يمكنك المحاولة مجددًا.','[]'::jsonb,'_GLOBAL'),
    
    -- Blacklisted
    ('PAYMENT_BLOCKED','fr','🚫 Suite à des incidents précédents, tu dois payer l''intégralité d''avance. Contacte le restaurant pour plus d''infos.','[]'::jsonb,'_GLOBAL'),
    ('PAYMENT_BLOCKED','ar','🚫 بسبب حوادث سابقة، يجب الدفع المسبق بالكامل. تواصل مع المطعم للمزيد.','[]'::jsonb,'_GLOBAL')
ON CONFLICT DO NOTHING;

-- =============================================================================
-- 9. Grants
-- =============================================================================
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'n8n') THEN
    EXECUTE 'GRANT SELECT, INSERT, UPDATE ON public.payment_intents TO n8n';
    EXECUTE 'GRANT SELECT, INSERT ON public.payment_history TO n8n';
    EXECUTE 'GRANT SELECT, INSERT, UPDATE ON public.customer_payment_profiles TO n8n';
    EXECUTE 'GRANT SELECT, INSERT, UPDATE ON public.restaurant_payment_config TO n8n';
    EXECUTE 'GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO n8n';
    EXECUTE 'GRANT EXECUTE ON FUNCTION public.calculate_deposit TO n8n';
    EXECUTE 'GRANT EXECUTE ON FUNCTION public.create_payment_intent TO n8n';
    EXECUTE 'GRANT EXECUTE ON FUNCTION public.confirm_deposit_payment TO n8n';
    EXECUTE 'GRANT EXECUTE ON FUNCTION public.collect_cod_payment TO n8n';
    EXECUTE 'GRANT EXECUTE ON FUNCTION public.update_customer_payment_profile TO n8n';
  END IF;
END $$;

COMMIT;

-- =============================================================================
-- ROLLBACK INSTRUCTIONS:
-- DROP FUNCTION IF EXISTS public.update_customer_payment_profile;
-- DROP FUNCTION IF EXISTS public.collect_cod_payment;
-- DROP FUNCTION IF EXISTS public.confirm_deposit_payment;
-- DROP FUNCTION IF EXISTS public.create_payment_intent;
-- DROP FUNCTION IF EXISTS public.calculate_deposit;
-- DROP TABLE IF EXISTS public.restaurant_payment_config;
-- DROP TABLE IF EXISTS public.customer_payment_profiles;
-- DROP TABLE IF EXISTS public.payment_history;
-- DROP TABLE IF EXISTS public.payment_intents;
-- DROP TYPE IF EXISTS payment_status_enum;
-- DROP TYPE IF EXISTS payment_method_enum;
-- =============================================================================

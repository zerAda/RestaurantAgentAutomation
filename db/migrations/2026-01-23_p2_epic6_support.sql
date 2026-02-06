BEGIN;

-- EPIC6 Support (P2)
-- - Human handoff via support tickets
-- - Lightweight FAQ (full-text search)

-- =========================
-- Support tickets
-- =========================

CREATE TABLE IF NOT EXISTS public.support_tickets (
  ticket_id        bigserial PRIMARY KEY,
  tenant_id        uuid NOT NULL REFERENCES public.tenants(tenant_id) ON DELETE CASCADE,
  restaurant_id    uuid NOT NULL REFERENCES public.restaurants(restaurant_id) ON DELETE CASCADE,

  channel          text NOT NULL CHECK (channel IN ('whatsapp','instagram','messenger')),
  conversation_key text NOT NULL,
  customer_user_id text NOT NULL,

  status           text NOT NULL DEFAULT 'OPEN' CHECK (status IN ('OPEN','ASSIGNED','CLOSED')),
  priority         text NOT NULL DEFAULT 'NORMAL' CHECK (priority IN ('LOW','NORMAL','HIGH')),
  reason_code      text NOT NULL DEFAULT 'HELP' CHECK (reason_code IN ('HELP','DELIVERY_AMBIGUOUS','PAYMENT_ISSUE','FAQ_FALLBACK','OTHER')),
  subject          text NULL,
  context_json     jsonb NOT NULL DEFAULT '{}'::jsonb,

  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now(),
  closed_at        timestamptz NULL
);

-- Avoid spam tickets: at most one active ticket per conversation (OPEN/ASSIGNED)
CREATE UNIQUE INDEX IF NOT EXISTS ux_support_ticket_active_conversation
  ON public.support_tickets(restaurant_id, conversation_key)
  WHERE status IN ('OPEN','ASSIGNED');

CREATE INDEX IF NOT EXISTS idx_support_tickets_status_rest
  ON public.support_tickets(restaurant_id, status, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_support_tickets_customer
  ON public.support_tickets(restaurant_id, channel, customer_user_id, created_at DESC);

-- Messages log for audit/debug
CREATE TABLE IF NOT EXISTS public.support_ticket_messages (
  id              bigserial PRIMARY KEY,
  ticket_id        bigint NOT NULL REFERENCES public.support_tickets(ticket_id) ON DELETE CASCADE,
  direction        text NOT NULL CHECK (direction IN ('INBOUND','OUTBOUND','INTERNAL')),
  from_user_id     text NULL,
  to_user_id       text NULL,
  body_text        text NOT NULL,
  meta_json        jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at       timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_support_ticket_messages_ticket
  ON public.support_ticket_messages(ticket_id, created_at DESC);

-- Assignments (admin takes a ticket)
CREATE TABLE IF NOT EXISTS public.support_assignments (
  id              bigserial PRIMARY KEY,
  ticket_id       bigint NOT NULL REFERENCES public.support_tickets(ticket_id) ON DELETE CASCADE,
  admin_user_id   text NOT NULL,
  assigned_at     timestamptz NOT NULL DEFAULT now(),
  released_at     timestamptz NULL,
  UNIQUE(ticket_id, released_at)
);

CREATE INDEX IF NOT EXISTS idx_support_assignments_admin
  ON public.support_assignments(admin_user_id, assigned_at DESC);

-- =========================
-- FAQ entries (RAG light)
-- =========================

CREATE TABLE IF NOT EXISTS public.faq_entries (
  faq_id         bigserial PRIMARY KEY,
  tenant_id      uuid NOT NULL REFERENCES public.tenants(tenant_id) ON DELETE CASCADE,
  restaurant_id  uuid NOT NULL REFERENCES public.restaurants(restaurant_id) ON DELETE CASCADE,
  locale         text NOT NULL CHECK (lower(locale) IN ('fr','ar')),
  question       text NOT NULL,
  answer         text NOT NULL,
  tags           text[] NOT NULL DEFAULT '{}'::text[],
  is_active      boolean NOT NULL DEFAULT true,
  search_tsv     tsvector,
  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_faq_entries_active_rest_locale
  ON public.faq_entries(restaurant_id, locale)
  WHERE is_active;

CREATE INDEX IF NOT EXISTS idx_faq_entries_search
  ON public.faq_entries USING GIN(search_tsv);

CREATE OR REPLACE FUNCTION public.faq_entries_tsv_update()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.search_tsv :=
    setweight(to_tsvector('simple', coalesce(NEW.question,'')), 'A') ||
    setweight(to_tsvector('simple', array_to_string(coalesce(NEW.tags,'{}'::text[]),' ')), 'B') ||
    setweight(to_tsvector('simple', coalesce(NEW.answer,'')), 'C');
  NEW.updated_at := now();
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_faq_entries_tsv ON public.faq_entries;
CREATE TRIGGER trg_faq_entries_tsv
BEFORE INSERT OR UPDATE OF question, answer, tags
ON public.faq_entries
FOR EACH ROW
EXECUTE FUNCTION public.faq_entries_tsv_update();

-- =========================
-- Message templates for Support (L10N)
-- (guarded: only if message_templates exists)
-- =========================

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema='public' AND table_name='message_templates'
  ) THEN
    INSERT INTO public.message_templates(tenant_id, template_key, locale, content, variables)
    VALUES
      ('_GLOBAL','SUPPORT_HANDOFF_ACK','fr','🧑‍💬 Merci. Un agent va vous contacter rapidement.','[]'::jsonb),
      ('_GLOBAL','SUPPORT_HANDOFF_ACK','ar','🧑‍💬 شكراً. سيتواصل معك أحد الموظفين قريباً.','[]'::jsonb),
      ('_GLOBAL','FAQ_NO_MATCH','fr','Je n'ai pas trouvé de réponse. Je te mets en relation avec un agent.','[]'::jsonb),
      ('_GLOBAL','FAQ_NO_MATCH','ar','لم أجد إجابة. سأحوّلك إلى موظف.','[]'::jsonb)
    ON CONFLICT (template_key, locale, tenant_id) DO NOTHING;
  END IF;
END $$;

COMMIT;

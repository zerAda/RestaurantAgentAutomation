# Workflow Inventory

**Generated**: 2026-04-06  
**Source**: `config/workflow_registry.json`  
**Total Workflows**: 98

---

## A. Shared Platform Core (18 workflows)

Always-on platform primitives. Module: `platform_runtime`

| Key | Trigger | Exposure | Auth | Tenant-Scoped | External Systems |
| :--- | :--- | :--- | :--- | :--- | :--- |
| W0_CONFIG_READER | executeWorkflow | worker_only | No | No | strapi, redis |
| W0_REDIS_HELPER | executeWorkflow | worker_only | No | No | redis |
| W0_META_VERIFY_UNIFIED | webhook | public | No | No | meta |
| W0_MODULE_GUARD | executeWorkflow | worker_only | No | Yes | strapi |
| W15_OUTBOX_WORKER | schedule | worker_only | No | No | redis, strapi |
| W18_MEDIA_FETCH_WORKER | schedule | worker_only | No | No | meta, redis |
| W8_DLQ_HANDLER | schedule | worker_only | No | No | redis |
| W8_DLQ_REPLAY | webhook | admin_only | Yes | No | redis |
| W8_OPS | schedule | worker_only | No | No | redis, strapi, postgres |
| W16_HEALTHZ | webhook | public | No | No | redis, postgres |
| W17_HEALTH_MONITOR | schedule | worker_only | No | No | redis, strapi |
| W_QUEUE_METRICS | schedule | worker_only | No | No | redis |
| W_REDIS_MONITOR | schedule | worker_only | No | No | redis |
| W_ERROR_HANDLER | executeWorkflow | worker_only | No | No | strapi |
| W_AUDIT_WRITE | webhook | internal | Yes | Yes | postgres |
| W_AUDIT_QUERY | webhook | admin_only | Yes | Yes | postgres |
| W_AUDIT_ARCHIVE | schedule | worker_only | No | No | postgres |
| W_L10N_DETECT | executeWorkflow | worker_only | No | No | — |
| W_LLM_INTENT | executeWorkflow | worker_only | No | No | ollama |

## B. Order Bot Core (7 workflows)

Base conversational commerce engine. Module: `order_bot_core`

| Key | Trigger | Exposure | Auth | Tenant-Scoped |
| :--- | :--- | :--- | :--- | :--- |
| W4_CORE | executeWorkflow | worker_only | No | Yes |
| W4.1_ROUTER | executeWorkflow | worker_only | No | Yes |
| W4.2_CART_MANAGER | executeWorkflow | worker_only | No | Yes |
| W4.3_FAQ_AGENT | executeWorkflow | worker_only | No | No |
| W10_CUSTOMER_DELIVERY_QUOTE | webhook | protected_public | No | Yes |
| W12_ADMIN_ORDERS | webhook | admin_only | Yes | Yes |
| W9_ADMIN_PING | webhook | admin_only | Yes | No |

## C. Channel Packs

### WhatsApp (4 workflows) — `channel_whatsapp`

| Key | Trigger | Exposure | Guard Wired |
| :--- | :--- | :--- | :--- |
| W1_IN_WA | webhook | public | ✅ Yes |
| W5_OUT_WA | executeWorkflow | worker_only | N/A |
| W14_ADMIN_WA_SUPPORT_CONSOLE | executeWorkflow | admin_only | N/A |
| W0_META_VERIFY_UNIFIED | webhook | public | N/A (shared) |

### Instagram (2 workflows) — `channel_instagram`

| Key | Trigger | Exposure | Guard Wired |
| :--- | :--- | :--- | :--- |
| W2_IN_IG | webhook | public | ✅ Yes |
| W6_OUT_IG | executeWorkflow | worker_only | N/A |

### Messenger (2 workflows) — `channel_messenger`

| Key | Trigger | Exposure | Guard Wired |
| :--- | :--- | :--- | :--- |
| W3_IN_MSG | webhook | public | ✅ Yes |
| W7_OUT_MSG | executeWorkflow | worker_only | N/A |

### TikTok (3 workflows) — `channel_tiktok`

| Key | Trigger | Exposure | Guard Wired |
| :--- | :--- | :--- | :--- |
| W1_IN_TIKTOK | webhook | public | ✅ Yes |
| W5_OUT_TIKTOK | executeWorkflow | worker_only | N/A |
| W_TIKTOK_PUBLISHER | webhook | internal | N/A |

## D. Payment (3 workflows) — `payment`

| Key | Trigger | Exposure | Guard Wired |
| :--- | :--- | :--- | :--- |
| W_PAYMENT_CHARGILY | webhook | protected_public | No |
| W_PAYMENT_CALLBACK | webhook | public | No |
| W_ORDER_FINALIZER | webhook | internal | ✅ Yes |

## E. Delivery & Dispatch (15 workflows) — `delivery_dispatch`

| Key | Trigger | Exposure |
| :--- | :--- | :--- |
| W11_ADMIN_DELIVERY_ZONES | webhook | admin_only |
| W_LOGISTICS_PRO | webhook | internal |
| W_DRIVER_DISPATCH | webhook | internal |
| W_DRIVER_ROUTER | webhook | protected_public |
| W_DRIVER_ACTIONS | webhook | protected_public |
| W_DRIVER_BOT | webhook | internal |
| W_DRIVER_ONBOARDING | webhook | internal |
| W_DRIVER_GAMIFICATION | webhook | internal |
| W_DRIVER_AVAILABLE_LIST | webhook | internal |
| W_DRIVER_HISTORY | webhook | protected_public |
| W_DRIVER_OTP_VERIFY | webhook | protected_public |
| W53_DYNAMIC_KITCHEN_LOAD | schedule | worker_only |
| W58_DYNAMIC_SURGE | schedule | worker_only |
| W_WEATHER_TRIGGER | schedule | worker_only |
| W_HIVE_MIND_DISPATCH | webhook | internal |

## F. Inventory (6 workflows) — `inventory`

| Key | Trigger | Exposure |
| :--- | :--- | :--- |
| W_INVENTORY_ORCHESTRATOR | webhook | internal |
| W_INVENTORY_SYNC | executeWorkflow | worker_only |
| W_LOW_STOCK_ALERT | executeWorkflow | worker_only |
| W55_PREDICTIVE_86ING | schedule | worker_only |
| W_MENU_VALIDATOR | executeWorkflow | worker_only |
| W56_STRAPI_DIALECT_SYNC | executeWorkflow | worker_only |

## G. Kiosk & In-Store (5 workflows) — `kiosk_instore`

| Key | Trigger | Exposure | Guard Wired |
| :--- | :--- | :--- | :--- |
| W_KIOSK_ORDER | webhook | protected_public | ✅ Yes |
| W_QR_TABLE_DETECTOR | executeWorkflow | worker_only | N/A |
| W25_GAMIFICATION_WHEEL | webhook | protected_public | No |
| W60_KITCHEN_CLOUD_PRINT | webhook | internal | No |
| W_THE_USUAL | webhook | internal | No |

## H. Voice (4 workflows) — `voice`

| Key | Trigger | Exposure | Guard Wired |
| :--- | :--- | :--- | :--- |
| W_STT_PIPELINE | webhook | internal | No |
| W_TTS_PIPELINE | webhook | internal | No |
| W30_VOICE_CALL_INIT | webhook | public | ✅ Yes |
| W31_VOICE_ORDER_CONFIRM | executeWorkflow | worker_only | N/A |

## I. Loyalty & CRM (5 workflows) — `loyalty_crm`

| Key | Trigger | Exposure |
| :--- | :--- | :--- |
| W_LOYALTY_ENGINE | webhook | internal |
| W50_CART_ABANDONMENT | schedule | worker_only |
| W51_VIP_WIN_BACK | schedule | worker_only |
| W_UPSELL_ENGINE | webhook | internal |
| W61_REVIEW_CATCHER | schedule | worker_only |

## J. Growth & Marketing (14 workflows) — `growth_marketing`

| Key | Trigger | Exposure |
| :--- | :--- | :--- |
| W_TRACKING_FUNNEL | webhook | protected_public |
| W_BOT_FUNNEL_HOOK | executeWorkflow | worker_only |
| W_FUNNEL_ANALYZER | schedule | worker_only |
| W_AI_FUNNEL_LEARNER | schedule | worker_only |
| W_GROWTH_AGENT | executeWorkflow | worker_only |
| W_REVENUE_INTELLIGENCE | schedule | worker_only |
| W_MARKETING_AUTOPILOT | schedule | worker_only |
| W_OMNICHANNEL_CONTENT_GEN | webhook | admin_only |
| W_CONTENT_SCHEDULER | schedule | worker_only |
| W_CONTENT_AUDITOR | schedule | worker_only |
| W_AD_MANAGER | schedule | worker_only |
| W21_CAMPAIGN_BLASTER | schedule | worker_only |
| W_AI_STRATEGY_ADVISOR | schedule | worker_only |
| W_INCEPTION_PROTOCOL | webhook | admin_only |

## K. Admin AI & Intelligence (6 workflows) — `admin_ai_intelligence`

| Key | Trigger | Exposure |
| :--- | :--- | :--- |
| W_ADMIN_AGENT | webhook | admin_only |
| W_ADMIN_AI_AGENT | webhook | admin_only |
| W_ADMIN_LIVE_MONITOR | schedule | worker_only |
| W_ADMIN_PROACTIVE_AGENT | schedule | worker_only |
| W_CORTEX_REGISTRY | executeWorkflow | worker_only |
| W_RALPHE_OMNISCIENT | schedule | admin_only |

## L. Experimental / Review (4 workflows) — `experimental`

| Key | Trigger | Notes |
| :--- | :--- | :--- |
| W4_CORE_ALGERIAN_STUB | executeWorkflow | Stale/duplicate variant of W4_CORE |
| W4_CORE_MENU_GROUNDED | executeWorkflow | Experimental grounded menu variant |
| W20_ASSET_ENHANCER | webhook | Admin-only asset processing |
| W_CMS_SYNC | webhook | Unclear ownership, stale integration |

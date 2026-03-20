# ENV_REFERENCE — RESTO BOT

Document env vars by service. Mark whether SECRET.

## Conventions

- SECRET vars must NOT be logged.
- Prefer secrets via files mounted into containers where possible.

## Gateway / Traefik

- `DOMAIN` (SECRET? no): Base domain for routing (e.g. `ralphe.com`)

## Strapi CMS

- `STRAPI_API_TOKEN` (SECRET? yes): Master Token for n8n to call Strapi
- `JWT_SECRET` (SECRET? yes): Used to sign Admin JWT tokens
- `DATABASE_URL` (SECRET? yes): Postgres connection string for Strapi
- `N8N_INTERNAL_IPS` (SECRET? no): Comma-separated list of n8n container IPs to bypass rate limiting. Example: `172.20.0.5,172.20.0.6`. Find with `docker inspect n8n | grep IPAddress`. Required for auth-ratelimit.ts C-05 fix to function properly.

## n8n Automation

- `WEBHOOK_URL` (SECRET? no): Base URL for webhooks (public facing)
- `N8N_BASIC_AUTH` (SECRET? yes): HTTP Basic Auth for n8n incoming webhooks

## External APIs (in n8n or Strapi)

- `OPENAI_API_KEY` (SECRET? yes): Used for core AI reasoning (Chat, Orders)
- `REPLICATE_API_TOKEN` (SECRET? yes): Used for Flux.1 image generation
- `WHATSAPP_TOKEN` (SECRET? yes): Cloud API token for sending WhatsApp MSGs
- `CHARGILY_API_KEY` (SECRET? yes): ePaiement CIB/Edahabia Algeria
- `TWILIO_ACCOUNT_SID` & `TWILIO_AUTH_TOKEN` (SECRET? yes): Twilio Voice integrations
- `VAPI_TOKEN` (SECRET? yes): Vapi.ai for Voice Agents
- `SUPABASE_URL` & `SUPABASE_ANON_KEY` (SECRET? yes): Realtime Websocket KDS

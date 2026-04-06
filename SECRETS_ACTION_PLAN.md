# SECRETS ACTION PLAN — Exhaustive Missing Variables
> Generated: 2026-03-28 | Resto Bot v3.3.6

---

## ✅ ALREADY SET (do nothing)

| Variable | Value | Source |
|---|---|---|
| `META_APP_ID` | `2042838606278243` | Provided by user |
| `META_APP_SECRET` | `8afe4ed4ae...` | Provided by user |
| `META_SIGNATURE_REQUIRED` | `warn` | Set in .env |
| `META_VERIFY_TOKEN` | `ea3ab821...` | Already in .env.production |
| `IG_APP_ID` | `26980747731525961` | Provided by user (test-IG) |
| `IG_APP_SECRET` | `5ebe40d2ce...` | Provided by user (test-IG) |
| `REDIS_CREDENTIAL_ID` | `43SDqJYMGa6RvFqW` | From n8n DB (memory) |

---

## 🔴 CRITICAL — Must fetch via web agent (blocks production)

### GROUP A — Meta Developer Portal
**URL:** https://developers.facebook.com/apps/2042838606278243/

| Variable | Where to get | Status |
|---|---|---|
| `WA_PHONE_NUMBER_ID` | App → WhatsApp → API Setup → Phone number ID | ❌ MISSING |
| `WA_API_TOKEN` | App → WhatsApp → API Setup → Temporary/Permanent token | ❌ MISSING |
| `IG_PAGE_ID` | App → Instagram → Basic Display → Instagram Business Account ID | ❌ MISSING |
| `IG_API_TOKEN` | App → Instagram → Access Tokens → Generate token | ❌ MISSING |
| `MSG_PAGE_ID` | App → Messenger → Settings → Page → Page ID | ❌ MISSING |
| `MSG_API_TOKEN` | App → Messenger → Settings → Access Tokens | ❌ MISSING |

**Agent web steps (GROUP A):**
```
1. Navigate: https://developers.facebook.com/apps/2042838606278243/whatsapp-business/wa-dev-console/
   → Screenshot Phone number ID + copy token

2. Navigate: https://developers.facebook.com/apps/26980747731525961/instagram-basic-display/
   → Screenshot Page ID + generate access token

3. Navigate: https://developers.facebook.com/apps/2042838606278243/messenger/settings/
   → Screenshot Page ID + copy access token
```

---

### GROUP B — TikTok For Developers
**URL:** https://developers.tiktok.com/apps/

| Variable | Where to get | Status |
|---|---|---|
| `TIKTOK_CLIENT_KEY` | TikTok Developer Portal → App → App Key | ❌ MISSING |
| `TIKTOK_CLIENT_SECRET` | TikTok Developer Portal → App → App Secret | ❌ MISSING |
| `TIKTOK_ACCESS_TOKEN` | TikTok Developer Portal → Authorization → Access Token | ❌ MISSING |
| `TIKTOK_REFRESH_TOKEN` | TikTok Developer Portal → Authorization → Refresh Token | ❌ MISSING |
| `TIKTOK_API_TOKEN` | TikTok Messaging API → Token (if enabled) | ❌ MISSING |
| `TIKTOK_PIXEL_ID` | TikTok Ads Manager → Assets → Events → Pixel | ❌ MISSING |

**Agent web steps (GROUP B):**
```
1. Navigate: https://developers.tiktok.com/apps/
   → Find app → copy Client Key + Client Secret

2. Navigate: https://ads.tiktok.com/ → Assets → Events → Web Events
   → Find Pixel → copy Pixel ID

3. TikTok messaging token: only available if TikTok for Business Messaging API is approved
```

---

### GROUP C — Marketing Ads (Facebook/Meta Ads)
**URL:** https://business.facebook.com/

| Variable | Where to get | Status |
|---|---|---|
| `META_PIXEL_ID` | Meta Events Manager → Pixel → Pixel ID | ❓ Not in .env yet |
| `META_AD_ACCOUNT_ID` | Meta Business Suite → Ad Accounts | ❓ Not in .env yet |
| `FACEBOOK_PAGE_ID` | Meta Business Suite → Pages | ❓ Not in .env yet |

---

## 🟡 OPTIONAL — Fill when services activated

| Variable | Service | Status |
|---|---|---|
| `STRAPI_API_TOKEN` | **Strapi CMS** — n8n→CMS auth, cortex workflows | 🔴 CRITICAL |
| `OPENAI_API_KEY` | OpenAI (fallback vision) | Optional (Ollama is primary) |
| `REPLICATE_API_TOKEN` | Replicate (image gen) | Optional |
| `ELEVENLABS_API_KEY` | ElevenLabs (TTS premium) | Optional |
| `VAPI_API_KEY` | Vapi (voice AI) | Optional |
| `SMS_API_URL` + `SMS_API_KEY` | SMS provider | Optional |
| `OPENWEATHER_API_KEY` | Weather (delivery ETAs) | Optional |
| `SLACK_WEBHOOK_URL` | Alert notifications | Optional |
| `CHARGILY_API_KEY` | Chargily payments (DZ) | Optional |
| `TWILIO_ACCOUNT_SID` + `TWILIO_AUTH_TOKEN` | Twilio SMS | Optional |
| `SUPABASE_URL` + `SUPABASE_ANON_KEY` | Supabase (if used) | Optional |
| `STRAPI_API_TOKEN` | **CRITICAL** — n8n→CMS auth (cortex workflows) | 🔴 MISSING |

---

## 🔧 BROWSER AGENT FIX

The `mcp__ruflo__browser_*` tools require `agent-browser` CLI to be installed globally.

**Fix — run this once in a terminal:**
```bash
npm install -g @ruflo/agent-browser
```
If that package doesn't exist, try:
```bash
npm install -g agent-browser
```
Or check ruflo installation:
```bash
npm list -g | grep ruflo
npx ruflo doctor
```

**Verify fix:**
```bash
agent-browser --version
```

---

## 📋 INJECTION ORDER (once values collected)

1. **Fill now** (have values): ✅ Done — META_APP_ID, IG_APP_ID, IG_APP_SECRET
2. **Fill next** (need web agent): WA_PHONE_NUMBER_ID, WA_API_TOKEN, IG_PAGE_ID, IG_API_TOKEN
3. **Fill after**: TikTok group, MSG group
4. **Fill when ready**: Optional services (OpenAI, Vapi, etc.)

After each fill: sync `.env.production` → VPS with:
```bash
scp .env.production deploy@72.60.190.192:/opt/resto/current/.env
ssh deploy@72.60.190.192 "cd /opt/resto/current && docker compose -f docker-compose.hostinger.prod.yml up -d n8n n8n-worker"
```

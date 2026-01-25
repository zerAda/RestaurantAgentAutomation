# Smoke tests (v3.0)

## Prérequis
- `.env` configuré
- DNS : `console.<domain>` et `api.<domain>` pointent vers le VPS
- Stack up : `docker compose -f docker-compose.hostinger.prod.yml up -d`

## 1) Console privée (doit refuser hors allowlist / sans auth)
```bash
curl -i https://console.${DOMAIN_NAME}/
```

## 2) API health
```bash
curl -i https://api.${DOMAIN_NAME}/healthz
```

## 3) Webhooks inbound (token requis)
```bash
curl -i -X POST "https://api.${DOMAIN_NAME}/v1/inbound/whatsapp" \
  -H "Content-Type: application/json" \
  -H "x-webhook-token: ${WEBHOOK_SHARED_TOKEN}" \
  -d '{"text":"pizza margarita","from":"+33600000000","msgId":"t1"}'
```

### 3.b) Contrôles sécurité (logs)

*Token invalide* : la réponse HTTP reste **200** (mode `onReceived`), mais l'événement **AUTH_DENY** doit être écrit dans `security_events`.

```bash
curl -i -X POST "https://api.${DOMAIN_NAME}/v1/inbound/whatsapp" \
  -H "Content-Type: application/json" \
  -H "x-webhook-token: invalid-token" \
  -d '{"text":"test","from":"+33600000000","msgId":"t1-deny"}'
```

*Audio URL interdite (SSRF)* : l'événement **AUDIO_URL_BLOCKED** doit être écrit dans `security_events`.

```bash
curl -i -X POST "https://api.${DOMAIN_NAME}/v1/inbound/whatsapp" \
  -H "Content-Type: application/json" \
  -H "x-webhook-token: ${WEBHOOK_SHARED_TOKEN}" \
  -d '{"audioUrl":"http://127.0.0.1/evil.ogg","from":"+33600000000","msgId":"t1-audio-block"}'
```

*Token en query* : **désactivé par défaut** (risque de fuite dans les logs). Pour tester :

```bash
# DOIT logguer AUTH_DENY si ALLOW_QUERY_TOKEN=false
curl -i -X POST "https://api.${DOMAIN_NAME}/v1/inbound/whatsapp?token=${WEBHOOK_SHARED_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"text":"test","from":"+33600000000","msgId":"t1-query"}'
```

## 4) Aliases legacy (optionnel)
```bash
curl -i -X POST "https://api.${DOMAIN_NAME}/v1/inbound/wa-incoming-v16" \
  -H "Content-Type: application/json" \
  -H "x-webhook-token: ${WEBHOOK_SHARED_TOKEN}" \
  -d '{"text":"couscous","from":"+33600000000","msgId":"t2"}'
```

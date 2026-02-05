# BATTERIE DE 100 TESTS - RESTO BOT v3.2.4

**Date:** 2026-01-29
**Scope:** Meta Integration (WA/IG/MSG) Production Ready

---

## SECTION 1: META VERIFY GET (10 tests)

| ID | Test | Commande | Attendu |
|----|------|----------|---------|
| T1.01 | WA verify mode=subscribe valid token | `curl -s "$API/v1/inbound/whatsapp?hub.mode=subscribe&hub.verify_token=$TOKEN&hub.challenge=test123"` | HTTP 200, body=`test123` |
| T1.02 | WA verify mode=subscribe invalid token | `curl -s "$API/v1/inbound/whatsapp?hub.mode=subscribe&hub.verify_token=WRONG&hub.challenge=test123"` | HTTP 403 |
| T1.03 | WA verify mode=invalid | `curl -s "$API/v1/inbound/whatsapp?hub.mode=WRONG&hub.verify_token=$TOKEN&hub.challenge=test123"` | HTTP 400 |
| T1.04 | WA verify missing challenge | `curl -s "$API/v1/inbound/whatsapp?hub.mode=subscribe&hub.verify_token=$TOKEN"` | HTTP 400 |
| T1.05 | IG verify mode=subscribe valid token | `curl -s "$API/v1/inbound/instagram?hub.mode=subscribe&hub.verify_token=$TOKEN&hub.challenge=ig123"` | HTTP 200, body=`ig123` |
| T1.06 | IG verify invalid token | `curl -s "$API/v1/inbound/instagram?hub.mode=subscribe&hub.verify_token=BAD&hub.challenge=ig123"` | HTTP 403 |
| T1.07 | MSG verify mode=subscribe valid token | `curl -s "$API/v1/inbound/messenger?hub.mode=subscribe&hub.verify_token=$TOKEN&hub.challenge=msg123"` | HTTP 200, body=`msg123` |
| T1.08 | MSG verify invalid token | `curl -s "$API/v1/inbound/messenger?hub.mode=subscribe&hub.verify_token=BAD&hub.challenge=msg123"` | HTTP 403 |
| T1.09 | Verify underscore notation (hub_mode) | `curl -s "$API/v1/inbound/whatsapp?hub_mode=subscribe&hub_verify_token=$TOKEN&hub_challenge=alt123"` | HTTP 200, body=`alt123` |
| T1.10 | Verify Content-Type text/plain | `curl -sI "$API/v1/inbound/whatsapp?hub.mode=subscribe&hub.verify_token=$TOKEN&hub.challenge=ct"` | Content-Type: text/plain |

---

## SECTION 2: META PAYLOAD PARSING NATIF (15 tests)

| ID | Test | Payload | Attendu |
|----|------|---------|---------|
| T2.01 | WA text message parsing | `{"object":"whatsapp_business_account","entry":[{"changes":[{"value":{"messages":[{"from":"212612345678","id":"wamid.xxx","type":"text","text":{"body":"Bonjour"}}]}}]}]}` | envelope.from=`212612345678`, envelope.text=`Bonjour` |
| T2.02 | WA image message parsing | `{"object":"whatsapp_business_account","entry":[{"changes":[{"value":{"messages":[{"from":"212612345678","id":"wamid.img","type":"image","image":{"id":"img123","mime_type":"image/jpeg"}}]}}]}]}` | envelope.attachments[0].type=`image` |
| T2.03 | WA audio message parsing | `{"object":"whatsapp_business_account","entry":[{"changes":[{"value":{"messages":[{"from":"212612345678","id":"wamid.aud","type":"audio","audio":{"id":"aud123","mime_type":"audio/ogg"}}]}}]}]}` | envelope.attachments[0].type=`audio` |
| T2.04 | WA button reply parsing | `{"object":"whatsapp_business_account","entry":[{"changes":[{"value":{"messages":[{"from":"212612345678","id":"wamid.btn","type":"interactive","interactive":{"type":"button_reply","button_reply":{"id":"btn_order"}}}]}}]}]}` | envelope.text=`btn_order` |
| T2.05 | WA location message | `{"object":"whatsapp_business_account","entry":[{"changes":[{"value":{"messages":[{"from":"212612345678","id":"wamid.loc","type":"location","location":{"latitude":36.75,"longitude":3.04}}]}}]}]}` | envelope.attachments[0].type=`location` |
| T2.06 | WA status message (ignore) | `{"object":"whatsapp_business_account","entry":[{"changes":[{"value":{"statuses":[{"id":"wamid.xxx","status":"delivered"}]}}]}]}` | HTTP 200, NO processing (status ignored) |
| T2.07 | IG text message parsing | `{"object":"instagram","entry":[{"messaging":[{"sender":{"id":"12345"},"message":{"mid":"m_ig","text":"Hello IG"}}]}]}` | envelope.from=`12345`, envelope.text=`Hello IG` |
| T2.08 | IG story reply parsing | `{"object":"instagram","entry":[{"messaging":[{"sender":{"id":"12345"},"message":{"mid":"m_story","text":"Nice!","reply_to":{"story":{"id":"story123"}}}}]}]}` | envelope.text=`Nice!`, meta.story_reply=true |
| T2.09 | MSG text message parsing | `{"object":"page","entry":[{"messaging":[{"sender":{"id":"67890"},"message":{"mid":"m_msg","text":"Hello Messenger"}}]}]}` | envelope.from=`67890`, envelope.text=`Hello Messenger` |
| T2.10 | MSG postback parsing | `{"object":"page","entry":[{"messaging":[{"sender":{"id":"67890"},"postback":{"payload":"GET_STARTED"}}]}]}` | envelope.text=`GET_STARTED`, type=`postback` |
| T2.11 | MSG attachment parsing | `{"object":"page","entry":[{"messaging":[{"sender":{"id":"67890"},"message":{"mid":"m_att","attachments":[{"type":"image","payload":{"url":"https://..."}}]}}]}]}` | envelope.attachments[0].type=`image` |
| T2.12 | Multi-entry batch (WA) | `{"object":"whatsapp_business_account","entry":[{...msg1},{...msg2}]}` | Both messages processed |
| T2.13 | Empty messages array | `{"object":"whatsapp_business_account","entry":[{"changes":[{"value":{"messages":[]}}]}]}` | HTTP 200, no error |
| T2.14 | Missing entry field | `{"object":"whatsapp_business_account"}` | HTTP 200, log warning |
| T2.15 | Invalid object type | `{"object":"unknown_platform","entry":[...]}` | HTTP 200, log warning |

---

## SECTION 3: SIGNATURE HMAC X-Hub-Signature-256 (15 tests)

| ID | Test | Mode | Signature | Attendu |
|----|------|------|-----------|---------|
| T3.01 | WA valid signature enforce | enforce | valid sha256 | HTTP 200 |
| T3.02 | WA invalid signature enforce | enforce | sha256=invalid | HTTP 401 |
| T3.03 | WA missing signature enforce | enforce | (none) | HTTP 401 |
| T3.04 | WA valid signature warn | warn | valid sha256 | HTTP 200, log OK |
| T3.05 | WA invalid signature warn | warn | sha256=invalid | HTTP 200, log WARNING |
| T3.06 | WA missing signature warn | warn | (none) | HTTP 200, log WARNING |
| T3.07 | WA any signature off | off | any | HTTP 200 |
| T3.08 | IG valid signature enforce | enforce | valid sha256 | HTTP 200 |
| T3.09 | IG invalid signature enforce | enforce | sha256=bad | HTTP 401 |
| T3.10 | MSG valid signature enforce | enforce | valid sha256 | HTTP 200 |
| T3.11 | MSG invalid signature enforce | enforce | sha256=bad | HTTP 401 |
| T3.12 | Timing-safe comparison | enforce | similar but wrong | HTTP 401, no timing leak |
| T3.13 | Empty body signature | enforce | sha256 of {} | HTTP 200 if matches |
| T3.14 | Wrong prefix (sha1) | enforce | sha1=xxx | HTTP 401 |
| T3.15 | Uppercase header | enforce | X-HUB-SIGNATURE-256 | HTTP 200 (case insensitive) |

---

## SECTION 4: FAST ACK < 1s (5 tests)

| ID | Test | Scenario | Attendu |
|----|------|----------|---------|
| T4.01 | WA response time | POST valid payload | Response < 1000ms |
| T4.02 | IG response time | POST valid payload | Response < 1000ms |
| T4.03 | MSG response time | POST valid payload | Response < 1000ms |
| T4.04 | Response before processing | POST + slow DB | HTTP 200 returned before DB insert completes |
| T4.05 | Async processing | Check execution log | CORE workflow triggered asynchronously |

---

## SECTION 5: AUTHENTIFICATION (15 tests)

| ID | Test | Scenario | Attendu |
|----|------|----------|---------|
| T5.01 | Meta signature auth (WA) | Valid sig, no token | authMode=`meta_signature` |
| T5.02 | Meta signature auth (IG) | Valid sig, no token | authMode=`meta_signature` |
| T5.03 | Meta signature auth (MSG) | Valid sig, no token | authMode=`meta_signature` |
| T5.04 | API client token auth | Valid token hash | authMode=`api_client` |
| T5.05 | Legacy shared token allowed | LEGACY_SHARED_ALLOWED=true | authMode=`legacy_shared` |
| T5.06 | Legacy shared token blocked | LEGACY_SHARED_ALLOWED=false | HTTP 401 or deny logged |
| T5.07 | Token in query string blocked | ALLOW_QUERY_TOKEN=false | Token ignored |
| T5.08 | Token in query string allowed | ALLOW_QUERY_TOKEN=true | Token accepted (deprecated) |
| T5.09 | Bearer token header | Authorization: Bearer xxx | Token extracted |
| T5.10 | X-Api-Token header | X-Api-Token: xxx | Token extracted |
| T5.11 | X-Webhook-Token header | X-Webhook-Token: xxx | Token extracted |
| T5.12 | No auth at all | No sig, no token | authMode=`deny` |
| T5.13 | Scope check inbound:write | Valid token, scope OK | scopeOk=true |
| T5.14 | Scope check missing | Valid token, no scope | scopeOk=false |
| T5.15 | Wildcard scope | scope=`*` | scopeOk=true |

---

## SECTION 6: IDEMPOTENCE & DEDUPLICATION (10 tests)

| ID | Test | Scenario | Attendu |
|----|------|----------|---------|
| T6.01 | New message (Redis) | First time msg_id | isNew=true, SET in Redis |
| T6.02 | Duplicate message (Redis) | Same msg_id again | isNew=false, no processing |
| T6.03 | New message (DB fallback) | Redis down | DB idempotency check works |
| T6.04 | Dedupe TTL expiry | msg_id after 48h | Treated as new |
| T6.05 | Different channel same msg_id | WA + IG same ID | Both processed (channel prefix) |
| T6.06 | DEDUPE_ENABLED=false | Config disabled | Always isNew=true |
| T6.07 | Redis error handling | Connection refused | Fallback to DB, no crash |
| T6.08 | Concurrent same msg_id | Parallel requests | Only one processed |
| T6.09 | Redis SET with TTL | Check key expiry | Key expires after DEDUPE_TTL_SEC |
| T6.10 | DB idempotency constraint | ON CONFLICT DO NOTHING | inserted=0 for dupe |

---

## SECTION 7: RATE LIMITING (5 tests)

| ID | Test | Scenario | Attendu |
|----|------|----------|---------|
| T7.01 | Under limit | 5 msgs in 30s | All processed |
| T7.02 | At limit | 6 msgs in 30s | 6th processed (<=6) |
| T7.03 | Over limit | 7 msgs in 30s | 7th rate-limited |
| T7.04 | Reset after window | Wait 30s, send again | Processed |
| T7.05 | Per-conversation isolation | User A at limit, User B OK | B not affected |

---

## SECTION 8: OUTBOUND META GRAPH API (15 tests)

| ID | Test | Scenario | Attendu |
|----|------|----------|---------|
| T8.01 | WA text send | replyText only | POST to graph.facebook.com, messaging_product=whatsapp |
| T8.02 | WA template send | templateName set | type=template in body |
| T8.03 | WA button send | buttons array | type=interactive, button format |
| T8.04 | IG text send | replyText only | POST to PAGE_ID/messages, recipient.id |
| T8.05 | IG quick reply send | buttons array | quick_replies format |
| T8.06 | MSG text send | replyText only | POST to PAGE_ID/messages |
| T8.07 | MSG button template | buttons array | attachment.type=template |
| T8.08 | Retry on 429 | Rate limit response | Wait retry-after, retry |
| T8.09 | Retry on 500 | Server error | Exponential backoff retry |
| T8.10 | No retry on 400 | Client error | Immediate fail to DLQ |
| T8.11 | Max retries exhausted | 3 failures | Message to DLQ |
| T8.12 | Token missing | WA_API_TOKEN empty | Error logged, no crash |
| T8.13 | URL missing | WA_SEND_URL empty | Error logged, no crash |
| T8.14 | Outbox store | Before send | Key in Redis |
| T8.15 | Outbox clear on success | After 200 | Key deleted |

---

## SECTION 9: DLQ (DEAD LETTER QUEUE) (5 tests)

| ID | Test | Scenario | Attendu |
|----|------|----------|---------|
| T9.01 | DLQ push on failure | Send fails | Entry in ralphe:dlq |
| T9.02 | DLQ entry format | Check structure | channel, error, payload, timestamp |
| T9.03 | DLQ replay workflow | W8_DLQ_REPLAY trigger | Message re-processed |
| T9.04 | DLQ alert threshold | >10 items | Alert triggered |
| T9.05 | DLQ count metric | Query Redis LLEN | Count returned |

---

## SECTION 10: ENVELOPE CANONIQUE (10 tests)

| ID | Test | Scenario | Attendu |
|----|------|----------|---------|
| T10.01 | WA envelope fields | Parse native | channel=whatsapp, provider=wa |
| T10.02 | IG envelope fields | Parse native | channel=instagram, provider=ig |
| T10.03 | MSG envelope fields | Parse native | channel=messenger, provider=msg |
| T10.04 | Timestamp normalization | Unix epoch -> ISO | 2026-01-29T12:00:00.000Z format |
| T10.05 | msg_id extracted | From wamid/mid | Correct ID |
| T10.06 | user_id extracted | From phone/PSID | Correct ID |
| T10.07 | Text extracted | From body/text | Correct text |
| T10.08 | Attachments array | From attachments | Correct structure |
| T10.09 | correlation_id generated | New request | UUID format |
| T10.10 | tenant_context source | Meta sig auth | source=meta_signature |

---

## SECTION 11: ANTI-REPLAY (5 tests)

| ID | Test | Scenario | Attendu |
|----|------|----------|---------|
| T11.01 | Fresh timestamp | Now - 10s | timestampValid=true |
| T11.02 | Old timestamp | Now - 600s | timestampValid=false (too_old) |
| T11.03 | Future timestamp | Now + 120s | timestampValid=false (future) |
| T11.04 | REPLAY_CHECK_ENABLED=false | Old timestamp | Always valid |
| T11.05 | Unparseable timestamp | "invalid" | timestampValid=true (fallback) |

---

## SECTION 12: TENANT CONTEXT SEAL (5 tests)

| ID | Test | Scenario | Attendu |
|----|------|----------|---------|
| T12.01 | Seal generated | After auth | tenant_context_seal = sha256 hash |
| T12.02 | Seal verified | Before CORE | No error |
| T12.03 | Seal tampered | Modified tenant_context | TENANT_CONTEXT_TAMPERED error |
| T12.04 | Seal missing | No seal field | Verification passes (backward compat) |
| T12.05 | Seal content | Check hash | Matches JSON.stringify(tenant_context) |

---

## SECTION 13: DATABASE LOGGING (5 tests)

| ID | Test | Scenario | Attendu |
|----|------|----------|---------|
| T13.01 | inbound_messages insert | Valid message | Row created |
| T13.02 | security_events deny | Auth failure | event_type logged |
| T13.03 | security_events contract | Invalid payload | CONTRACT_VALIDATION_FAILED |
| T13.04 | idempotency_keys insert | New msg | Row created |
| T13.05 | conversation_quarantine check | Quarantined user | Query returns quarantined=1 |

---

## SECTION 14: HEALTHCHECKS (5 tests)

| ID | Test | Scenario | Attendu |
|----|------|----------|---------|
| T14.01 | Traefik ping | Dashboard :8080 | HTTP 200 |
| T14.02 | Postgres healthcheck | pg_isready | success |
| T14.03 | Redis healthcheck | redis-cli ping | PONG |
| T14.04 | n8n main webhook | /webhook/health | HTTP 200 (if configured) |
| T14.05 | Gateway nginx | / | HTTP response |

---

## SECTION 15: ROLLBACK SCENARIOS (5 tests)

| ID | Test | Scenario | Attendu |
|----|------|----------|---------|
| T15.01 | META_SIGNATURE_REQUIRED=off | Disable sig check | All requests pass |
| T15.02 | LEGACY_SHARED_ALLOWED=true | Re-enable legacy | Token works |
| T15.03 | DEDUPE_ENABLED=false | Disable Redis | Falls back to DB |
| T15.04 | Mock API fallback | WA_SEND_URL=mock | Uses mock-api |
| T15.05 | Workflow disable | Set active=false | No processing |

---

## SECTION 16: NATIVE META PAYLOAD SMOKE TESTS (12 tests) - P1-01

Tests with **real Meta native payload formats** (not canonical internal format).

| ID | Test | Fixture | Endpoint | Attendu |
|----|------|---------|----------|---------|
| T16.01 | WA text native | `wa_text.json` | /v1/inbound/whatsapp | HTTP 200, parsed correctly |
| T16.02 | WA image native | `wa_image.json` | /v1/inbound/whatsapp | HTTP 200, media detected |
| T16.03 | WA button reply | `wa_button_reply.json` | /v1/inbound/whatsapp | HTTP 200, interactive parsed |
| T16.04 | WA list reply | `wa_list_reply.json` | /v1/inbound/whatsapp | HTTP 200, list_reply parsed |
| T16.05 | IG text native | `ig_text.json` | /v1/inbound/instagram | HTTP 200, parsed correctly |
| T16.06 | IG image native | `ig_image.json` | /v1/inbound/instagram | HTTP 200, media detected |
| T16.07 | IG postback native | `ig_postback.json` | /v1/inbound/instagram | HTTP 200, postback parsed |
| T16.08 | IG story mention | `ig_story_mention.json` | /v1/inbound/instagram | HTTP 200, story detected |
| T16.09 | MSG text native | `msg_text.json` | /v1/inbound/messenger | HTTP 200, parsed correctly |
| T16.10 | MSG image native | `msg_image.json` | /v1/inbound/messenger | HTTP 200, media detected |
| T16.11 | MSG postback native | `msg_postback.json` | /v1/inbound/messenger | HTTP 200, postback parsed |
| T16.12 | MSG quick reply | `msg_quick_reply.json` | /v1/inbound/messenger | HTTP 200, quick_reply parsed |

**Fixtures:** `scripts/smoke/payloads/*.json`
**Runner:** `scripts/smoke/run.sh`

### Payload Formats

**WhatsApp** (object: `whatsapp_business_account`):
```json
{"object":"whatsapp_business_account","entry":[{"changes":[{"value":{"messages":[...]}}]}]}
```

**Instagram** (object: `instagram`):
```json
{"object":"instagram","entry":[{"messaging":[{"sender":{"id":"..."},"message":{...}}]}]}
```

**Messenger** (object: `page`):
```json
{"object":"page","entry":[{"messaging":[{"sender":{"id":"..."},"message":{...}}]}]}
```

---

## EXECUTION

```bash
# Run full battery (100 tests)
./scripts/test_battery.sh

# Run specific section
./scripts/test_battery.sh --section 2

# Run with verbose output
./scripts/test_battery.sh --verbose

# Run in CI mode (fail on first error)
./scripts/test_battery.sh --ci

# --- NATIVE PAYLOAD SMOKE TESTS (P1-01) ---

# Run native Meta payload smoke tests
./scripts/smoke/run.sh

# Run specific section (1-8)
./scripts/smoke/run.sh --section 3

# Run with verbose output
./scripts/smoke/run.sh --verbose

# Quick Meta-specific tests
./scripts/smoke_meta.sh
```

---

## CRITERES DE PASSAGE

- **PASS:** Test retourne le resultat attendu
- **FAIL:** Test ne retourne pas le resultat attendu
- **SKIP:** Test non applicable (config manquante)

**Seuil minimal pour deployment prod:** 95/100 PASS (95%)
**Seuil critique:** Sections 1-3 doivent etre 100% PASS

---

**Total tests:** 112 (100 + 12 native payload)
**Date derniere mise a jour:** 2026-01-31

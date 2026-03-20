# Orchestration — EPIC5 (Execution Agents)

## Phase 1 — Design (PO → Archi → DB)
- **Agent 12 (PO Virtuel)** : backlog + AC + release plan.
- **Agent 1 (Architecte L10N)** : architecture runtime + ADR.
- **Agent 2 (DB Specialist)** : schéma `message_templates` / `customer_preferences` + seeds + fonctions tracking.

**Gates**
- Docs alignées avec code.
- Migration idempotente + rollback.

## Phase 2 — Dev Core (parallel)
- **Agent 3 (Backend L10N)** : W4_CORE patch (script-first, renderer, buttons, sticky, darija).
- **Agent 5 (API Multilingue)** : (N/A EPIC5 pur)’assurer que payloads incluent locale si nécessaire.
- **Agent 4 (NLP Darija)** + **Agent 6 (Linguiste)** : dictionnaire darija + qualité AR/FR.
- **Agent 7 (Templates)** : catalogue + templates seed.

**Sync points**
- Contracts `templates` + `templateVars` (obj) stables.
- Keys templates stables.

## Phase 3 — Qualité & données
- **Agent 8 (Data tests)** : datasets JSON + fixtures.
- **Agent 9 (QA)** : scripts tests + intégration integrity gate.
- **Agent 11 (UX)** : plan de test WA.
- **Agent 10 (DevOps flags)** : env example + doc release.

## Phase 4 — Intégration
- **Agent 13 (Coordinator)** : vérifie compatibilité, génère `INTERFACES.md`, rapport.

---

## Checklist d’intégration (Coordinator)
- [ ] Docs cohérentes (pas de flags fantômes)
- [ ] Migration appliquable/rollbackable
- [ ] Workflows JSON valides (jq)
- [ ] `scripts/integrity_gate.sh` passe
- [ ] Tests L10N passent
- [ ] Admin WA templates fonctionne

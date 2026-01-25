# Décisions (ADR) — EPIC5 Localisation

## ADR-001 — Script-first plutôt que préférence
**Décision** : la langue des réponses interactives est déterminée par la présence de **script arabe** dans le message entrant (`ar` sinon `fr`).

**Raisons**
- UX simple : pas de paramétrage obligatoire.
- Compatible darija (script arabe ou latin) avec règle claire.

**Conséquences**
- Un utilisateur peut recevoir FR même s’il a mis `LANG AR`, tant qu’il écrit en latin. C’est voulu.

---

## ADR-002 — `LANG FR|AR` conservé pour préférences persistées
**Décision** : `LANG ...` n’override pas la règle script-first, mais alimente `customer_preferences` pour les **notifications** (tracking).

---

## ADR-003 — Templates en DB + overrides tenant
**Décision** : stocker les messages transactionnels dans `message_templates`.

**Raisons**
- Modifications rapides via console WhatsApp.
- Variantes FR/AR gérées au même endroit.

---

## ADR-004 — Renderer safe + allowlist variables
**Décision** : renderer non-exécutable + allowlist des variables (`message_templates.variables`).

**Raisons**
- Empêche injections, évite crashes.

---

## ADR-005 — Admin sans UI (WhatsApp-first)
**Décision** : pilotage templates via `W14_ADMIN_WA_SUPPORT_CONSOLE`.

**Raisons**
- “No UI” demandé : time-to-market + cohérence channel.

---

## ADR-006 — Sticky AR optionnel
**Décision** : sticky AR derrière flags (`L10N_STICKY_AR_*`).

**Raisons**
- Évite surprises en prod.
- Permet d’améliorer UX darija translit progressivement.

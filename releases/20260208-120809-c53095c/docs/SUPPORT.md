# EPIC6 — Support (P2)

Objectif : permettre un **handoff humain** et une **FAQ “RAG light”** sur WhatsApp, **sans créer de nouvelle UI**.

## Feature flags

Dans `.env` (ou variables d'environnement n8n) :

```bash
SUPPORT_ENABLED=true
FAQ_ENABLED=true

# Console admin WhatsApp (pilotage)
ADMIN_WA_CONSOLE_ENABLED=true
ADMIN_WA_CONSOLE_WORKFLOW_ID=<id n8n de W14>
```

## Handoff humain (SUP-001)

### Déclencheurs

- Message utilisateur : `help`, `aide`, `agent`, `support` (case-insensitive) ➜ création ticket.
- Règle “adresse livraison ambiguë” : après `DELIVERY_ADDRESS_MAX_ATTEMPTS`, le bot bascule en handoff.
- Fallback FAQ : pas de réponse FAQ satisfaisante ➜ création ticket.

### Données

- `support_tickets` : un ticket par conversation (un seul actif à la fois).
- `support_ticket_messages` : log des échanges.
- `support_assignments` : prise en charge par un admin.

### Réponse client

Le client reçoit un message localisé : `SUPPORT_HANDOFF_ACK` (FR/AR).

## FAQ (SUP-002) — “RAG light”

FAQ stockée en base (table `faq_entries`) + recherche full-text (`tsvector` + GIN).

- Si match : le bot renvoie `answer`.
- Sinon : message `FAQ_NO_MATCH` + escalade vers support.

Objectif produit : viser ~80% de questions courantes (horaires, paiement, livraison, etc.) résolues sans escalade.

## Pilotage admin sur WhatsApp (pas de UI)

Le pilotage support se fait via une **console admin WhatsApp** (préfixe `!`).

### Pré-requis RBAC

L’admin doit être enregistré dans `restaurant_users` avec :

- `channel='whatsapp'`
- `role IN ('admin','owner')`

### Commandes

- `!help` : aide.
- `!tickets [open|all]` : liste tickets.
- `!take <ticket_id>` : prendre un ticket.
- `!close <ticket_id>` : clôturer.
- `!reply <ticket_id> <message>` : répondre au client.

Notes :

- Les commandes sont **traitées côté inbound** (W1) et routées vers `W14`.
- Les réponses admin sont envoyées via l’outbox (`outbound_messages`) comme les autres messages.

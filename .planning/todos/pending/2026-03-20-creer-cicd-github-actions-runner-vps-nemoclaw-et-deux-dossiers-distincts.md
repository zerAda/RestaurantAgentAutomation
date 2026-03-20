---
created: 2026-03-20T20:03:16.911Z
title: Créer CI/CD GitHub Actions + runner VPS NemoClaw et deux dossiers distincts
area: general
files:
  - .planning/phases/07-nemoclaw-telegram-bot-nvidia-nim-integration-and-reliability-improvements/
---

## Problem

Le projet contient actuellement deux entités distinctes :
1. **RestaurantBot** — le stack RESTO BOT v3.3.x (n8n + Strapi + Traefik + gateway...)
2. **NemoClaw** — le bot Telegram IA NVIDIA NIM (telegram-bridge + openclaw)

Ces deux projets coexistent dans le même repo sans séparation claire, ce qui complique :
- Le CI/CD (un seul pipeline pour tout)
- La navigation et la compréhension du code
- Les déploiements indépendants
- La création d'un repo GitHub dédié NemoClaw (prévu en phase 07-04)

De plus, NemoClaw n'a pas encore de pipeline CI/CD : pas de tests automatiques, pas de déploiement automatique sur le VPS, pas de self-hosted runner GitHub Actions.

## Solution

### 1. Restructuration locale en 2 dossiers distincts

Créer une arborescence claire :
```
project/           → RestaurantBot (existant, à garder tel quel)
nemoclaw/          → NemoClaw bot (nouveau dossier à la racine)
  ├── telegram-bridge-local.js
  ├── package.json
  ├── .github/workflows/
  └── README.md
```

OU deux repos GitHub séparés (à décider avec l'utilisateur) :
- `restaurant-bot` (repo actuel)
- `nemoclaw` (nouveau repo, créé en phase 07-04)

### 2. CI/CD GitHub Actions pour NemoClaw

- Workflow `ci.yml` : lint + tests sur push/PR
- Workflow `deploy.yml` : déploiement sur VPS via SSH
- Self-hosted runner GitHub Actions installé sur le VPS (service systemd)
- Secrets GitHub : `VPS_SSH_KEY`, `VPS_HOST`, `VPS_USER`
- Le runner tourne sous l'utilisateur `deploy` (même que RESTO BOT)

### 3. Questions à clarifier avec l'utilisateur

- Même repo (monorepo) ou deux repos séparés ?
- Le dossier NemoClaw local pointe vers `~/nemoclaw/` sur le VPS ou `/opt/nemoclaw/` ?
- Utiliser le même self-hosted runner que RESTO BOT ou un runner dédié NemoClaw ?

## Notes

- Phase 07-04 prévoit déjà la création d'un repo GitHub dédié NemoClaw
- Le plan 07-03 fixe le service systemd nemoclaw.service
- À planifier après la complétion de la phase 07

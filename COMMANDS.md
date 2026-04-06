# 🏗️ COMMANDS.md — Piloter Ralphé depuis OpenCode

> **Centre de commande** pour le projet RestaurantAgentAutomation.
> Stack: React · Strapi · n8n · Redis · Postgres · Docker · VPS Hostinger

---

## 📋 Table des Matières

1. [Setup Initial](#-setup-initial)
2. [Smart Routing (Budget 20€)](#-smart-routing-budget-20mois)
3. [Commandes VPS (Pro Skills)](#-commandes-vps-pro-skills)
4. [MCP Servers (Accès Direct Infra)](#-mcp-servers-accès-direct-infra)
5. [Workflows de Développement](#-workflows-de-développement)
6. [Optimisation PC Faible](#-optimisation-pc-faible)
7. [Estimation des Coûts](#-estimation-des-coûts)
8. [Troubleshooting](#-troubleshooting)

---

## 🔧 Setup Initial

### 1. Installer OpenCode
```bash
# Via npm (recommandé)
npm install -g opencode-ai

# Ou via binary direct (meilleur pour PC faible)
curl -fsSL https://opencode.ai/install | bash
```

### 2. Configurer la clé OpenRouter
```bash
# Définir la variable d'environnement
export OPENROUTER_API_KEY="sk-or-v1-VOTRE_CLE_ICI"

# Sous Windows PowerShell:
$env:OPENROUTER_API_KEY = "sk-or-v1-VOTRE_CLE_ICI"
```

### 3. Initialiser le projet
```bash
cd "c:\Users\mon pc\Desktop\ralphé_final_patch"
opencode init
```

### 4. Vérifier la configuration
```bash
opencode models         # Liste des modèles disponibles
opencode mcp list       # Vérifie les serveurs MCP
opencode web --port 4096 # Lancement sur le port Ralphé
```

---

## 💰 Smart-Routing (Budget <20€/mois)

### Architecture des modèles

| Rôle | Modèle | Raisonnement | Coût |
|------|--------|--------------|------|
| **Planner** | `deepseek/deepseek-reasoner` (R1) | **High** (Chain of Thought) | ~10% Budget |
| **Coder** | `moonshotai/kimi-k2.5` | **High** (128k Context) | ~60% Budget |
| **Auditor** | `deepseek/deepseek-reasoner` (R1) | **High** (Security/QA) | ~30% Budget |

### Comment ça marche

```
┌─────────────────────────────────────────────────────┐
│                    OpenCode TUI                      │
│                                                      │
│  /plan "Analyse l'erreur Redis timeout"              │
│    └──→ Kimi K2.5 (reasoning: high) ──→ Analyse      │
│                                                      │
│  /code "Fixe le script de backup Redis"              │
│    └──→ Kimi K2.5 (reasoning: medium) ──→ Code       │
│                                                      │
│  Prompt Caching: 90%+ (même modèle = cache garanti)  │
│    └──→ $0.42/M input, cache hit ≈ $0.04/M           │
└─────────────────────────────────────────────────────┘
```

### Règles d'optimisation coût
1. **Garder le system prompt identique** entre les sessions → maximise le cache hit
2. **Mode Plan pour réfléchir** (R1), **Mode Code pour exécuter** (V3)
3. **Petits contextes** : n'incluez que les fichiers nécessaires
4. **Éviter les régénérations** : soyez précis dans vos prompts

---

## 🖥️ Commandes VPS (Pro Skills)

### `/vps-health` — Diagnostic complet du VPS

```bash
# Depuis OpenCode, tapez:
/vps-health
```

**Affiche:**
- CPU / RAM / Disque du serveur
- État de tous les containers Docker
- Mémoire Redis (used vs max, evictions)
- Derniers logs Strapi CMS

### `/clear-cache` — Purger le cache Redis

```bash
# Purger toutes les clés Strapi
/clear-cache

# Purger un Content-Type spécifique
/clear-cache restaurants
/clear-cache menu-items
/clear-cache orders
```

**Fonctionnement:**
1. Scanne les clés Redis matchant `strapi::*` (ou le pattern donné)
2. Affiche le nombre de clés trouvées
3. Supprime en batch via `redis-cli DEL`

### `/qa-audit` — Audit de qualité Diamond-Grade (R1)

```bash
/qa-audit
```

**Vérifie:**
- Sécurité (injections, secrets hardcodés)
- Performance (indexation DB, usage Redis)
- Intégrité n8n (dependencies, credentials)
- Conformité AGENTS.md

### `/deploy-patch` — Déployer des modifications

```bash
# Déployer le CMS (par défaut)
/deploy-patch

# Déployer un service spécifique
/deploy-patch cms
/deploy-patch admin-dashboard
/deploy-patch kiosk-app
/deploy-patch gateway
```

**Pipeline:**
1. `rsync` des fichiers locaux → VPS (exclut `.git`, `node_modules`, `.env`, `secrets`)
2. Fix des line endings (CRLF → LF) pour les scripts bash
3. `docker compose build <service>` sur le VPS
4. `docker compose up -d <service>` redémarrage
5. Health check automatique

### `/redis-info` — Diagnostic Redis détaillé

```bash
/redis-info
```

**Affiche:** Toutes les métriques Redis (mémoire, clients, keyspace, replication, etc.)

### `/redis-keys` — Lister les clés Redis

```bash
/redis-keys
```

**Affiche:** Les 100 premières clés stockées dans Redis.

### `/n8n-status` — État des workflows

```bash
/n8n-status
```

**Affiche:**
- Status containers n8n-main + n8n-worker
- 15 dernières lignes de logs de chaque instance

### `/db-status` — Diagnostic PostgreSQL

```bash
/db-status
```

**Affiche:**
- Connectivité Postgres
- Nombre de connexions actives
- Taille des bases de données

### `/logs-tail` — Agrégateur de logs

```bash
# Tous les services critiques
/logs-tail

# Un service spécifique
/logs-tail cms
/logs-tail n8n-main
/logs-tail gateway
```

---

## 🔌 MCP Servers (Accès Direct Infra)

### Redis MCP
Permet à OpenCode d'interagir directement avec Redis.

```
Exemples de requêtes en langage naturel:
├── "Montre-moi toutes les clés Redis qui commencent par 'strapi'"
├── "Quelle est la mémoire utilisée par Redis?"
├── "Supprime la clé 'strapi::menu-items::list'"
└── "Publie un message sur le channel 'cache-invalidation'"
```

### SSH/VPS MCP
Permet d'exécuter des commandes sur le VPS de production.

```
Exemples:
├── "Montre les logs de n8n des 5 dernières minutes"
├── "Redémarre le container cms"
├── "Vérifie l'espace disque restant"
└── "Exécute le script de backup Postgres"
```

> ⚠️ **Sécurité**: Le serveur SSH utilise l'authentification par clé (`~/.ssh/id_ed25519`).
> Ne jamais utiliser de mot de passe en clair.

### Postgres MCP (n8n)
Accès direct à la base n8n pour inspecter les exécutions, workflows, et credentials.

```
Exemples:
├── "Montre les 10 dernières exécutions n8n en erreur"
├── "Combien de workflows actifs?"
├── "Liste les tables de la base n8n"
└── "Montre le schéma de la table execution_entity"
```

### Strapi CMS MCP
Accès direct aux données du restaurant (menu, commandes, clients) via l'API REST.

```
Exemples:
├── "Combien de commandes aujourd'hui?"
├── "Liste les items du menu avec un stock < 10"
├── "Montre les clients les plus actifs ce mois"
└── "Quels sont les types de contenu disponibles?"
```

---

## 🔄 Workflows de Développement

### Cycle de développement typique

```mermaid
graph TD
    A[Local: Modifier le code] --> B[/plan: Analyser l'impact]
    B --> C[/code: Implémenter les fixes]
    C --> D[make lint — Valider syntaxe]
    D --> E[make test-unit — Tests Python]
    E --> F[/deploy-patch cms — Déployer]
    F --> G[/vps-health — Vérifier]
    G --> H{OK?}
    H -->|Oui| I[✅ Done]
    H -->|Non| J[/logs-tail cms — Debug]
    J --> B
```

### Commandes Makefile existantes

| Commande | Description |
|----------|-------------|
| `make lint` | Valider Bash + JSON |
| `make test-unit` | Tests Python (contracts, L10N, templates) |
| `make test-battery` | 100 tests complets (stack requise) |
| `make smoke` | Smoke tests sur instance running |
| `make ci` | Pipeline CI complète locale |
| `make deploy` | Déploiement production complet |
| `make vps-status` | Status containers VPS |
| `make vps-logs` | Logs agrégés VPS |
| `make vps-ssh` | Session SSH interactive |

### Debugging avancé

```bash
# 1. Identifier le problème
/plan "Analyse pourquoi les commandes WhatsApp ne passent plus depuis 2h"

# 2. Inspecter les logs
/logs-tail n8n-main

# 3. Vérifier Redis (queue Bull)
/redis-keys

# 4. Vérifier la DB
# (via MCP Postgres, en langage naturel)
"Montre les exécutions n8n en erreur des 2 dernières heures"

# 5. Appliquer le fix
/code "Corrige le timeout dans le workflow W1_IN_WA.json"

# 6. Déployer
/deploy-patch
```

---

## ⚡ Optimisation PC Faible

### Stratégies appliquées

| Optimisation | Détail |
|-------------|--------|
| **`.opencodeignore`** | Exclut `node_modules`, `package-lock.json`, images, builds, vieilles phases |
| **LSP désactivé** | `"experimental": { "lsp": false }` — économise CPU en continu |
| **Modèle léger par défaut** | DeepSeek V3 (rapide, peu de tokens) pour le code quotidien |
| **Modèle lourd = à la demande** | DeepSeek R1 uniquement en mode `/plan` |
| **Pas de parallélisme** | Une seule session OpenCode à la fois |
| **WSL recommandé** | Windows I/O est lent — WSL2 x10 plus rapide |

### Recommandations hardware

```
Configuration minimale recommandée:
├── RAM: 8GB (4GB libre minimum pour OpenCode + Docker)
├── CPU: 2 cœurs
├── Disque: SSD (obligatoire pour les performances I/O)
└── Réseau: Connexion stable (SSH vers VPS)

Tips:
├── Fermer VS Code / IDE lourd pendant les sessions intensives
├── Utiliser Windows Terminal (léger) au lieu de PowerShell ISE
├── Désactiver l'antivirus en temps réel sur le dossier projet
└── Préférer WSL2 Ubuntu pour les commandes bash
```

---

## 💶 Estimation des Coûts

### Budget DeepSeek via OpenRouter (~20€/mois max)

| Activité | Modèle | Tokens/jour estimés | Coût/mois |
|----------|--------|---------------------|-----------|
| Planning / Debug | R1 | ~50k input + 10k output | ~4€ |
| Coding / Scripts | V3 | ~100k input + 30k output | ~6€ |
| Prompt Cache Savings | Auto | -90% sur tokens répétés | -9€ |
| **Total estimé** | | | **~10-15€** |

### Comment surveiller les coûts
1. Dashboard OpenRouter: [openrouter.ai/activity](https://openrouter.ai/activity)
2. Vérifier les cache hits dans les réponses API (`usage.cache_hit_tokens`)
3. Alerte budget: configurable dans OpenRouter settings

---

## 🔧 Troubleshooting

### MCP Server ne démarre pas

```bash
# Tester manuellement le serveur Redis MCP
npx -y @modelcontextprotocol/server-redis redis://localhost:6379

# Tester le serveur SSH MCP
npx -y @zibdie/ssh-mcp-server@latest

# Tester le serveur Postgres MCP
npx -y @modelcontextprotocol/server-postgres "postgresql://n8n:password@localhost:5432/n8n"
```

### SSH vers VPS échoue

```bash
# Vérifier la clé SSH
ssh -i ~/.ssh/id_ed25519 deploy@72.60.190.192

# Si permission denied:
chmod 600 ~/.ssh/id_ed25519
ssh-add ~/.ssh/id_ed25519
```

### Redis inaccessible depuis MCP

Le Redis du VPS n'est PAS exposé publiquement (sécurité).
Options:
1. **Tunnel SSH** : `ssh -L 6379:redis:6379 deploy@72.60.190.192` puis utiliser `redis://localhost:6379`
2. **Via SSH MCP** : Utiliser le serveur SSH pour exécuter `redis-cli` sur le VPS

### OpenCode trop lent

1. Vérifier `.opencodeignore` est bien chargé
2. Fermer les autres sessions OpenCode
3. Utiliser WSL2 au lieu de PowerShell natif
4. Réduire la taille du contexte (moins de fichiers ouverts)

---

## 📁 Architecture du Projet

```
RestaurantAgentAutomation/
├── .opencode.json          ← Configuration OpenCode (CE FICHIER)
├── .opencodeignore         ← Exclusions indexation (performance)
├── COMMANDS.md             ← Ce guide
├── docker-compose.*.yml    ← Compose files (base, dev, prod, ghcr)
├── Makefile                ← Commandes de développement
├── inventory-cms/          ← Strapi CMS (menus, commandes, clients)
├── admin-dashboard/        ← React admin panel
├── kiosk-app/              ← React kiosk (commandes sur place)
├── workflows/              ← 97 n8n workflows JSON
├── scripts/                ← 80+ scripts ops/test/deploy
├── infra/                  ← Redis, Nginx, Gateway configs
├── db/                     ← Migrations PostgreSQL
├── config/                 ← Schemas JSON
└── .github/workflows/      ← CI/CD pipeline
```

### Services Docker (Production)

| Service | Image | Rôle | Port interne |
|---------|-------|------|-------------|
| `postgres` | postgres:15-alpine | Base de données | 5432 |
| `pgbouncer` | edoburu/pgbouncer | Connection pooler | 6432 |
| `redis` | redis:7-alpine | Cache + Queue Bull | 6379 |
| `n8n-main` | n8n:2.9.4 | Orchestration (webhooks) | 5678 |
| `n8n-worker` | n8n:2.9.4 | Exécution workflows | - |
| `cms` | Strapi 4 (custom) | CMS restaurant | 1337 |
| `admin-dashboard` | React (Vite) | Panel admin | 80 |
| `kiosk-app` | React (Vite) | Borne de commande | 80 |
| `gateway` | nginx:1.27-alpine | API gateway | 8080 |
| `ollama` | ollama:0.6.2 | LLM local | 11434 |

### Redis Usage Map

```
Redis (256MB, allkeys-lru)
├── n8n Bull Queue           ← Job queue pour executions_mode=queue
├── strapi::*                ← Cache API Strapi (menus, items)
├── dedupe::*                ← Déduplication messages WhatsApp
├── session::*               ← Sessions conversation (sticky lang)
├── rate_limit::*            ← Rate limiting par sender
├── redis_monitor_check      ← Heartbeat monitoring (W_REDIS_MONITOR)
└── queue_consecutive_count  ← Compteur alertes queue (W_QUEUE_METRICS)
```

---

*Dernière mise à jour: 2026-03-29 | Projet: Ralphé v3.3.0*

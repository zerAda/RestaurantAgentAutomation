# Guide Pipeline CI/CD - Resto Bot v3.2.5

## Vue d'ensemble

Ce guide explique comment configurer et utiliser la pipeline CI/CD DevSecOps pour Resto Bot.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           ARCHITECTURE PIPELINE                              │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   GitHub Repository                                                          │
│        │                                                                     │
│        ▼                                                                     │
│   ┌─────────┐     ┌──────────────┐     ┌─────────────┐                      │
│   │   CI    │────▶│   Security   │────▶│     CD      │                      │
│   │ (Tests) │     │    Scan      │     │  (Deploy)   │                      │
│   └─────────┘     └──────────────┘     └──────┬──────┘                      │
│                                               │                              │
│                                               ▼                              │
│                                    ┌─────────────────┐                      │
│                                    │   VPS Hostinger │                      │
│                                    │  72.60.190.192  │                      │
│                                    │                 │                      │
│                                    │  ┌───────────┐  │                      │
│                                    │  │  Traefik  │  │                      │
│                                    │  │   (TLS)   │  │                      │
│                                    │  └─────┬─────┘  │                      │
│                                    │        │        │                      │
│                                    │  ┌─────▼─────┐  │                      │
│                                    │  │    n8n    │  │                      │
│                                    │  │  (main +  │  │                      │
│                                    │  │  worker)  │  │                      │
│                                    │  └─────┬─────┘  │                      │
│                                    │        │        │                      │
│                                    │  ┌─────▼─────┐  │                      │
│                                    │  │ PostgreSQL│  │                      │
│                                    │  │  + Redis  │  │                      │
│                                    │  └───────────┘  │                      │
│                                    └─────────────────┘                      │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Configuration GitHub (OBLIGATOIRE)

### 1. Créer le secret SSH

**C'est l'étape la plus importante !**

1. Aller dans votre repository GitHub
2. **Settings** > **Secrets and variables** > **Actions**
3. Cliquer **New repository secret**
4. Nom: `VPS_SSH_KEY`
5. Valeur: Coller le contenu de votre clé privée SSH

```bash
# Pour obtenir la clé (sur Windows):
type C:\Users\mon pc\.ssh\id_rsa
```

Copiez TOUT le contenu (y compris `-----BEGIN` et `-----END`).

### 2. Secret optionnel pour notifications

Si vous voulez recevoir des notifications Slack/Discord:

- Nom: `ALERT_WEBHOOK_URL`
- Valeur: URL du webhook (ex: `https://hooks.slack.com/services/xxx/xxx/xxx`)

---

## Les 6 Workflows

### 1. CI - Resto Bot (`ci.yml`)

**Déclencheur:** Push sur main, Pull Requests

**Ce qu'il fait:**
- Valide la syntaxe Bash des scripts
- Vérifie les fichiers YAML/JSON
- Scanne les secrets hardcodés
- Vérifie les gates de sécurité dans les workflows n8n
- Exécute les tests Python (schemas, L10N, templates, Darija)
- Crée un package de déploiement

**Jobs parallèles:**
```
┌──────────┐  ┌──────────────┐  ┌─────────────┐
│   Lint   │  │   Security   │  │   Python    │
│ & Syntax │  │    Gates     │  │   Tests     │
└────┬─────┘  └──────┬───────┘  └──────┬──────┘
     │               │                  │
     └───────────────┴──────────────────┘
                     │
                     ▼
              ┌──────────────┐
              │    Build     │
              │   Package    │
              └──────────────┘
```

---

### 2. Security Scan (`security-scan.yml`)

**Déclencheur:** Push, PR, Dimanche 2h UTC

**Ce qu'il fait:**
- **Gitleaks**: Détection de secrets dans le code
- **Trivy**: Scan des images Docker (n8n, postgres, redis, nginx, traefik)
- **SAST**: Audit des configurations Docker Compose et Nginx
- **Dependency scan**: Vulnérabilités Python et nodes n8n
- **SBOM**: Génération du Software Bill of Materials

---

### 3. CD - Deploy (`cd-deploy.yml`)

**Déclencheur:** Après CI réussi, ou manuellement

**Ce qu'il fait:**
1. **Preflight**: Vérifie VPS, espace disque, Docker
2. **Détection**: Premier déploiement vs mise à jour
3. **Backup** de la base de données et config avant déploiement
4. **Sync** du code vers le VPS via rsync/SSH
5. **DB Health**: Vérifie tables et migrations
6. **Health check** avec 15 tentatives
7. **Smoke tests** (5 tests: health, HTTPS, DB, Redis, API)
8. **Cleanup VPS** (Docker images, logs, backups)
9. **Auto-rollback** si échec
10. **Notification** du résultat

**Flux:**
```
Preflight → Backup → Deploy → DB Health → Smoke Tests → Cleanup → Notify
    │                   │         │            │           │
    │                   │         │            │           └── Prune Docker
    │                   │         │            │               Rotate logs
    │                   │         │            │               Clean backups
    │                   │         │            │
    │                   │         │            └── 5 tests automatiques
    │                   │         │
    │                   │         └── Vérifie migrations
    │                   │             Track dans _migrations
    │                   │
    │                   └── Détecte: first deploy vs update
    │
    └── Check VPS + disk (>2GB)
```

**Utilisation manuelle:**
1. Actions > CD - Deploy to VPS > Run workflow
2. Choisir `production` ou `staging`
3. Options:
   - Skip backup
   - Force full deploy (traiter comme premier déploiement)
   - Skip cleanup

---

### 4. Rollback (`rollback.yml`)

**Déclencheur:** Manuel uniquement

**Ce qu'il fait:**
- Restaure une configuration précédente
- Option: Restaurer aussi la base de données
- Crée un backup de sécurité avant le rollback

**Types de rollback:**
| Type | Restaure |
|------|----------|
| `config` | .env + secrets/ |
| `full` | config + base de données |

**Utilisation:**
1. Actions > Rollback Deployment > Run workflow
2. Choisir le type (`config` ou `full`)
3. Optionnel: Spécifier un backup précis
4. **Taper `ROLLBACK`** pour confirmer
5. Donner une raison (audit)

---

### 5. Scheduled Backup (`scheduled-backup.yml`)

**Déclencheur:** Automatique

| Schedule | Type | Rétention |
|----------|------|-----------|
| Tous les jours 3h UTC | daily | 7 jours |
| Dimanche 4h UTC | full | 4 semaines |

**Ce qu'il fait:**
- Dump PostgreSQL compressé
- Backup .env et secrets
- Vérification d'intégrité
- Rotation automatique des vieux backups

**Utilisation manuelle:**
1. Actions > Scheduled Backup > Run workflow
2. Choisir `daily` ou `full`

---

### 6. Health Monitor (`health-monitor.yml`)

**Déclencheur:** Toutes les 15 minutes

**Ce qu'il fait:**
- Ping `https://n8n.srv1258231.hstgr.cloud/healthz`
- Si échec: diagnostic sur le VPS (Docker, disque, mémoire)
- Alerte webhook si problème

---

## Chemins sur le VPS

| Chemin | Description |
|--------|-------------|
| `/docker/n8n/` | Stack Docker (compose, .env, secrets) |
| `/local-files/ralphe/n8n-project/` | Code source |
| `/local-files/backups/resto-bot/` | Backups |
| `/var/log/resto-bot/` | Logs déploiements/rollbacks |

---

## Commandes utiles

### Sur le VPS

```bash
# État des services
cd /docker/n8n && docker compose ps

# Logs n8n
docker compose logs -f n8n-main

# Logs tous services
docker compose logs --tail=50

# Redémarrer un service
docker compose restart n8n-main

# Backup manuel
docker compose exec -T postgres pg_dump -U n8n -d n8n | gzip > backup.sql.gz

# Voir les backups
ls -lh /local-files/backups/resto-bot/

# Voir les logs de déploiement
cat /var/log/resto-bot/deployments.log
```

### Localement

```bash
# Tester la connexion SSH
ssh -i ~/.ssh/id_rsa root@72.60.190.192 "echo OK"

# Sync manuel du code
rsync -avz --exclude='.git' ./ root@72.60.190.192:/local-files/ralphe/n8n-project/

# Test health check
curl https://n8n.srv1258231.hstgr.cloud/healthz
```

---

## Troubleshooting

### Le déploiement échoue

1. Vérifier que `VPS_SSH_KEY` est configuré dans GitHub Secrets
2. Vérifier les logs du job dans GitHub Actions
3. Se connecter au VPS et vérifier les logs Docker

### Health check échoue

```bash
# Sur le VPS
cd /docker/n8n
docker compose ps  # Tous les services sont "Up"?
docker compose logs n8n-main --tail=50  # Erreurs?
```

### Backup échoue

```bash
# Tester manuellement
cd /docker/n8n
docker compose exec postgres pg_isready -U n8n  # DB accessible?
```

### Rollback ne trouve pas de backup

```bash
# Lister les backups disponibles
ls -lh /local-files/backups/resto-bot/
```

---

## Sécurité

### Secrets à ne JAMAIS commiter

- `.env` (gitignored)
- `secrets/` (gitignored)
- Clés SSH privées
- Tokens API

### Bonnes pratiques

1. Toujours utiliser HTTPS
2. Ne jamais exposer les ports DB (5432) ou Redis (6379)
3. Garder les images Docker à jour (Dependabot activé)
4. Vérifier les rapports de sécurité hebdomadaires

---

## Résumé rapide

| Action | Workflow | Comment |
|--------|----------|---------|
| Tester le code | CI | Push sur main |
| Déployer | CD | Auto après CI ou manuel |
| Rollback | Rollback | Manuel + confirmation |
| Backup manuel | Scheduled Backup | Manuel |
| Vérifier santé | Health Monitor | Auto toutes les 15 min |
| Scan sécurité | Security Scan | Push ou hebdomadaire |

---

## URLs importantes

| Service | URL | Credentials |
|---------|-----|-------------|
| **n8n Console** | https://n8n.srv1258231.hstgr.cloud | admin / RestoAdmin2026! |
| **Adminer (DB)** | https://adminer.srv1258231.hstgr.cloud | admin / RestoAdmin2026! |
| **API Gateway** | https://api.srv1258231.hstgr.cloud | Token API |
| Health Check | https://n8n.srv1258231.hstgr.cloud/healthz | admin / RestoAdmin2026! |
| GitHub Actions | https://github.com/[votre-repo]/actions | - |

---

## Adminer - Gestion Base de Données

### Accès Web
- **URL:** https://adminer.srv1258231.hstgr.cloud
- **Username:** `admin`
- **Password:** `RestoAdmin2026!`

### Connexion PostgreSQL (dans Adminer)
| Champ | Valeur |
|-------|--------|
| System | PostgreSQL |
| Server | `postgres` |
| Username | `n8n` |
| Password | (voir `/docker/n8n/secrets/postgres_password`) |
| Database | `n8n` |

### Sécurité Adminer
- BasicAuth obligatoire (admin/RestoAdmin2026!)
- IP Allowlist configurable via `ADMIN_ALLOWED_IPS`
- Accès HTTPS uniquement
- Pas d'accès direct à la DB depuis l'extérieur

### Changer le mot de passe
```bash
# Sur le VPS
cd /docker/n8n
ADMIN_PASS=$(openssl passwd -apr1 'NOUVEAU_MOT_DE_PASSE')
echo "admin:${ADMIN_PASS}" > secrets/traefik_usersfile
chmod 600 secrets/traefik_usersfile
docker compose restart traefik
```

---

## Support

En cas de problème:
1. Vérifier les logs GitHub Actions
2. Se connecter au VPS via SSH
3. Consulter `/var/log/resto-bot/`
4. Vérifier `docker compose logs`

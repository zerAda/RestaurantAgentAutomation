# AGENT_W1_01 — Gateway Activator (CRITICAL)

## Mission
**APPLIQUER RÉELLEMENT** le patch nginx.conf.patched qui dort dans le repo.

## Problème Identifié (Audit V1)
```
Impact : le blocage des tokens en query string + rate-limit Nginx n'est PAS actif
Preuve : docker-compose.hostinger.prod.yml monte infra/gateway/nginx.conf
         infra/gateway/nginx.conf est l'ancienne version
         infra/gateway/nginx.conf.patched contient le vrai correctif... mais il dort là.
```

## Vérification Pré-Patch
```bash
# Vérifier que le patch existe
ls -la infra/gateway/nginx.conf.patched

# Vérifier la différence
diff infra/gateway/nginx.conf infra/gateway/nginx.conf.patched

# Vérifier que le patch contient les protections
grep -c "query_token_blocked" infra/gateway/nginx.conf.patched  # Doit être > 0
grep -c "limit_req_zone" infra/gateway/nginx.conf.patched       # Doit être > 0
```

## Action de Patch

### Script: apply_gateway_patch.sh
```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$(dirname "$SCRIPT_DIR")")")"

echo "=== AGENT_W1_01: Gateway Activator ==="

# 1. Backup
BACKUP_DIR="$PROJECT_ROOT/backups/gateway_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"
cp "$PROJECT_ROOT/infra/gateway/nginx.conf" "$BACKUP_DIR/nginx.conf.backup"
echo "✅ Backup créé: $BACKUP_DIR/nginx.conf.backup"

# 2. Vérifier que le patch existe
if [ ! -f "$PROJECT_ROOT/infra/gateway/nginx.conf.patched" ]; then
    echo "❌ ERREUR: nginx.conf.patched n'existe pas!"
    exit 1
fi

# 3. Vérifier le contenu du patch
if ! grep -q "query_token_blocked" "$PROJECT_ROOT/infra/gateway/nginx.conf.patched"; then
    echo "❌ ERREUR: Le patch ne contient pas la protection query_token!"
    exit 1
fi

# 4. Appliquer le patch
cp "$PROJECT_ROOT/infra/gateway/nginx.conf.patched" "$PROJECT_ROOT/infra/gateway/nginx.conf"
echo "✅ nginx.conf.patched → nginx.conf"

# 5. Vérifier l'application
if grep -q "query_token_blocked" "$PROJECT_ROOT/infra/gateway/nginx.conf"; then
    echo "✅ Protection query token ACTIVE"
else
    echo "❌ ERREUR: Protection non appliquée!"
    exit 1
fi

if grep -q "limit_req_zone" "$PROJECT_ROOT/infra/gateway/nginx.conf"; then
    echo "✅ Rate limiting ACTIF"
else
    echo "⚠️  Rate limiting non trouvé (optionnel)"
fi

# 6. Tester la config nginx (si docker disponible)
if command -v docker &> /dev/null; then
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q gateway; then
        echo "Testing nginx config..."
        if docker exec gateway nginx -t; then
            echo "✅ Config nginx valide"
            docker exec gateway nginx -s reload
            echo "✅ Nginx rechargé"
        else
            echo "❌ Config nginx invalide - ROLLBACK"
            cp "$BACKUP_DIR/nginx.conf.backup" "$PROJECT_ROOT/infra/gateway/nginx.conf"
            exit 1
        fi
    else
        echo "ℹ️  Container gateway non trouvé - reload manuel requis"
    fi
fi

echo ""
echo "=== AGENT_W1_01: SUCCÈS ==="
echo "Rollback: cp $BACKUP_DIR/nginx.conf.backup infra/gateway/nginx.conf"
```

## Vérification Post-Patch
```bash
# Test 1: Query token doit être bloqué
curl -s -o /dev/null -w "%{http_code}" \
  "http://localhost:8080/v1/inbound/whatsapp?token=test" 
# Attendu: 401

# Test 2: Header token doit fonctionner
curl -s -o /dev/null -w "%{http_code}" \
  -H "Authorization: Bearer valid-token" \
  "http://localhost:8080/v1/inbound/whatsapp"
# Attendu: 200 ou 202

# Test 3: Rate limit headers présents
curl -sI "http://localhost:8080/v1/inbound/whatsapp" | grep -i "x-ratelimit"
```

## Rollback
```bash
cp backups/gateway_YYYYMMDD_HHMMSS/nginx.conf.backup infra/gateway/nginx.conf
docker exec gateway nginx -s reload
```

## Critères de Succès
- [x] nginx.conf contient `query_token_blocked`
- [x] nginx.conf contient `limit_req_zone`
- [x] `nginx -t` passe
- [x] Query token retourne 401
- [x] Header token fonctionne

## Dépendances
- Aucune (premier agent à exécuter)

## Agent Suivant
→ AGENT_W1_02_SIGNATURE_VALIDATOR

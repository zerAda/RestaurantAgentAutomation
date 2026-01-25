# AGENT_W3_01 — L10N Activator (MEDIUM)

## Mission
**ACTIVER RÉELLEMENT** L10N qui est à false par défaut alors que c'est requis pour l'Algérie.

## Problème Identifié (Audit V5)
```
Impact : Algérie réelle = si tu réponds FR à quelqu'un qui écrit AR/Darja → abandon.
Preuve : config/.env.example a L10N_ENABLED=false 
         (le .patched le met à true, mais encore une fois : pas appliqué).
```

## Solution

### Étape 1: Appliquer .env.example.patched → .env.example

Le fichier `.env.example.patched` contient déjà:
```env
L10N_ENABLED=true
L10N_STICKY_AR_ENABLED=true
L10N_STICKY_AR_THRESHOLD=2
L10N_FALLBACK_LOCALE=fr
```

Mais il n'a PAS été appliqué!

### Étape 2: Vérifier que W4_CORE utilise ces flags

Dans W4_CORE.json, le code de détection locale doit:
1. Vérifier `L10N_ENABLED`
2. Détecter le script arabe
3. Appliquer sticky AR
4. Utiliser le fallback FR

### Script d'Application

```bash
#!/usr/bin/env bash
set -euo pipefail

echo "=== AGENT_W3_01: L10N Activator ==="

PROJECT_ROOT="$(dirname "$(dirname "$(dirname "$0")")")"
ENV_FILE="$PROJECT_ROOT/config/.env.example"
ENV_PATCHED="$PROJECT_ROOT/config/.env.example.patched"

# 1. Vérifier .env.example.patched
echo "Vérification de .env.example.patched..."

if [ -f "$ENV_PATCHED" ]; then
    if grep -q "L10N_ENABLED=true" "$ENV_PATCHED"; then
        echo "✅ L10N_ENABLED=true dans .env.example.patched"
    else
        echo "❌ L10N_ENABLED manquant dans .env.example.patched"
        exit 1
    fi
else
    echo "❌ .env.example.patched n'existe pas!"
    exit 1
fi

# 2. Appliquer le patch
echo "Application du patch..."
cp "$ENV_PATCHED" "$ENV_FILE"
echo "✅ .env.example.patched → .env.example"

# 3. Vérifier l'application
if grep -q "L10N_ENABLED=true" "$ENV_FILE"; then
    echo "✅ L10N_ENABLED=true ACTIF"
else
    echo "❌ L10N_ENABLED pas activé!"
    exit 1
fi

if grep -q "L10N_STICKY_AR_ENABLED=true" "$ENV_FILE"; then
    echo "✅ L10N_STICKY_AR_ENABLED=true ACTIF"
else
    echo "⚠️  L10N_STICKY_AR_ENABLED manquant"
fi

# 4. Vérifier W4_CORE
echo ""
echo "Vérification de W4_CORE.json..."

W4_CORE="$PROJECT_ROOT/workflows/W4_CORE.json"
if [ -f "$W4_CORE" ]; then
    if grep -q "L10N_ENABLED" "$W4_CORE"; then
        echo "✅ W4_CORE vérifie L10N_ENABLED"
    else
        echo "⚠️  W4_CORE ne semble pas vérifier L10N_ENABLED"
    fi
    
    if grep -q "arabicPattern\|[\u0600-\u06FF]" "$W4_CORE"; then
        echo "✅ W4_CORE détecte le script arabe"
    else
        echo "⚠️  Détection script arabe non trouvée"
    fi
else
    echo "❌ W4_CORE.json non trouvé!"
fi

# 5. Résumé
echo ""
echo "=== RÉSUMÉ L10N ==="
echo ""
grep -E "^L10N_|^LOCALE_" "$ENV_FILE" || echo "(aucune config L10N trouvée)"
echo ""
echo "=== ACTIONS REQUISES ==="
echo ""
echo "1. Copier ces valeurs dans votre .env de production:"
echo "   L10N_ENABLED=true"
echo "   L10N_STICKY_AR_ENABLED=true"
echo "   L10N_STICKY_AR_THRESHOLD=2"
echo "   L10N_FALLBACK_LOCALE=fr"
echo ""
echo "2. Redémarrer n8n workers"
echo ""
echo "3. Tester avec un message en arabe:"
echo '   curl -X POST ... -d '\''{"text":"مرحبا","from":"123",...}'\'''
echo "   → La réponse doit être en arabe"
```

## Vérification Post-Patch

### Test 1: Message arabe → Réponse arabe
```bash
curl -X POST "http://localhost:8080/v1/inbound/whatsapp" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "msg_id": "l10n-test-1",
    "from": "213555123456",
    "text": "مرحبا",
    "provider": "wa"
  }'
# Réponse doit contenir du texte arabe
```

### Test 2: Message français → Réponse française
```bash
curl -X POST "http://localhost:8080/v1/inbound/whatsapp" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "msg_id": "l10n-test-2",
    "from": "213555123456",
    "text": "Bonjour",
    "provider": "wa"
  }'
# Réponse doit être en français
```

### Test 3: Sticky AR (après réponse AR, bouton reste AR)
```bash
# 1. Envoyer message arabe
# 2. Recevoir réponse arabe avec boutons
# 3. Cliquer sur bouton (même si label FR)
# 4. Réponse doit rester en arabe
```

### Test 4: Commande LANG
```bash
# Forcer la langue
curl -X POST ... -d '{"text": "LANG FR", ...}'
# Les réponses suivantes doivent être en français
```

## Rollback
```env
L10N_ENABLED=false
```

## Critères de Succès
- [ ] .env.example contient L10N_ENABLED=true
- [ ] Message arabe → réponse arabe
- [ ] Message français → réponse française
- [ ] Sticky AR fonctionne
- [ ] Commande LANG fonctionne
- [ ] Templates FR et AR existent

## Agent Suivant
→ AGENT_W3_02_TEMPLATE_VALIDATOR

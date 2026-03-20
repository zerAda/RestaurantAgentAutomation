# Admin WhatsApp — Commandes Templates (EPIC5 L10N)

## Pré-requis
- `ADMIN_WA_CONSOLE_ENABLED=true`
- Workflow `W14 - ADMIN WA Support Console` importé et activé.
- L’admin doit être présent dans `api_clients` avec scope admin (déjà géré par EPIC6/OPSSECQA) et rôle `admin` ou `owner`.

## Règles importantes
- **On n’édite jamais `_GLOBAL`** depuis WhatsApp : la console écrit des overrides **par tenant**.
- Locale acceptée : `fr` ou `ar` (toute variante `ar-*` est normalisée en `ar`).
- **Auto-locale** : si le message admin contient de l’**arabe**, la réponse est renvoyée en **arabe** (si `STRICT_AR_OUT=true`).
- Longueur max contenu : 2000 chars (sécurité).

---

## Commandes

### 1) Lire un template
**Syntaxe**
- `!template get <KEY> [fr|ar]`

**Exemples**
- `!template get CORE_CLARIFY fr`
- `!template get WA_ORDER_STATUS_CONFIRMED ar`

**Résultat attendu**
- Renvoie le contenu actuel du tenant (override) ou le fallback `_GLOBAL` si aucun override.

---

### 2) Écrire un template (override tenant)
**Syntaxe**
- `!template set <KEY> [fr|ar] <CONTENT...>`

**Exemples**
- `!template set CORE_CLARIFY ar لم أفهم جيداً. هل يمكنك التوضيح؟`
- `!template set WA_ORDER_STATUS_READY fr 📦 Votre commande est prête (#{{order_id}}).{{eta}}`

**Notes**
- Pour les variables, utiliser la syntaxe `{{var}}`.
- Les variables non déclarées via `!template vars ...` sont ignorées au rendu.

---

### 3) Définir la liste des variables autorisées
**Syntaxe**
- `!template vars <KEY> [fr|ar] <var1,var2,...>`

**Exemples**
- `!template vars WA_ORDER_STATUS_CONFIRMED fr order_id,eta`
- `!template vars WA_ORDER_STATUS_DELIVERED ar order_id`

---

## Delivery Zones (pilotage WhatsApp)

> Permet de piloter rapidement les zones de livraison **sans UI** (WhatsApp admin).

### 1) Lister les zones
**Syntaxe**
- `!zone list`

**Résultat**
- Liste `wilaya / commune | fee | min | ETA | actif/inactif` (max 25 lignes dans la réponse).

### 2) Créer / Mettre à jour une zone
**Syntaxe (recommandée, séparateur “;”)**
- `!zone set <wilaya> ; <commune> ; <fee_cents> ; <min_cents> ; <eta_min> ; <eta_max> ; <active:true|false>`

**Exemples**
- `!zone set Alger ; Hydra ; 30000 ; 150000 ; 45 ; 60 ; true`
- `!zone set Oran ; Bir El Djir ; 0 ; 200000 ; 50 ; 70 ; true`

### 3) Supprimer une zone
**Syntaxe**
- `!zone del <wilaya> ; <commune>`

**Exemple**
- `!zone del Alger ; Hydra`

---

## Clés recommandées (catalogue)
Voir : `docs/TEMPLATE_CATALOG.md`.

## Dépannage
- Réponse “UNKNOWN” : vérifier la syntaxe (espaces) et le rôle admin.
- Template non trouvé : vérifier que la clé existe (ou créer via `set`).
- Rendu vide : vérifier `vars` (allowlist) + variables envoyées.

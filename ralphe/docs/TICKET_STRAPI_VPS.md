# Ticket de Déploiement : Connexion Strapi -> VPS PostgreSQL

**Objectif** : Connecter l'instance Strapi locale (ou conteneurisée) à la base de données PostgreSQL de production (VPS) et générer le Token API pour n8n.

## 1. Pré-requis

- Accès SSH au VPS.
- Connexion à la base de données PostgreSQL (`n8n` database) active.

## 2. Configuration Environnement (.env)

Sur le serveur de production (dans le dossier `inventory-cms`), modifiez le fichier `.env` pour pointer vers la base PostgreSQL du VPS (souvent via le réseau Docker interne ou IP locale).

```env
DATABASE_CLIENT=postgres
DATABASE_HOST=postgres      # Nom du service dans docker-compose
DATABASE_PORT=5432
DATABASE_NAME=n8n
DATABASE_USERNAME=n8n
DATABASE_PASSWORD=n8npass   # À récupérer dans les secrets
DATABASE_SSL=false
```

## 3. Génération du Token API

Une fois Strapi connecté à la base de données, lancez le script de génération de token :

```bash
cd project/inventory-cms
node scripts/init-token.js
```

## 4. Sauvegarde du Token

Copiez la valeur de `N8N_API_TOKEN` affichée dans le terminal.
Ajoutez cette valeur dans les variables d'environnement de **n8n** (service `n8n-main` et `n8n-worker` dans `docker-compose.hostinger.prod.yml`) :

```yaml
environment:
  - N8N_API_TOKEN=votre_token_ici
```

## 5. Redémarrage

Redémarrez les conteneurs pour appliquer les changements :

```bash
docker compose -f docker-compose.hostinger.prod.yml up -d
```

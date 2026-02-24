# RUNBOOK PRODUCTION: RALPHÉ SYSTEM

**Version**: 1.0 (Strict Audit Validated)
**Date**: 2026-02-05

---

## 🆘 RESTAURATION D'URGENCE (DISASTER RECOVERY)

### Cas 1 : Crash de la Base de Données (Postgres)

Si la base est corrompue ou perdue :

1. **Identifier le dernier backup** :

    ```bash
    ls -l backups/postgres/
    # Ex: backup_20260205_120000.sql.gz
    ```

2. **Lancer le script de restauration** :

    ```bash
    ./scripts/restore_postgres.sh backups/postgres/backup_20260205_120000.sql.gz
    ```

3. **Vérifier n8n** : `https://console.votre-domaine.com`

### Cas 2 : Perte des Images (Media Strapi)

Si le volume Docker `cms_uploads` est supprimé :

1. **Identifier le dernier backup média** :

    ```bash
    ls -l backups/media/
    # Ex: media_20260205_120000.tar.gz
    ```

2. **Restaurer le volume** :

    ```bash
    # Stop CMS
    docker compose -f docker-compose.hostinger.prod.yml stop cms
    
    # Extract to volume path (Attention: Path varies by OS/Docker setup)
    # Generic method via temporary container:
    docker run --rm -v cms_uploads:/data -v $(pwd)/backups/media:/backup alpine \
      tar xzf /backup/media_20260205_120000.tar.gz -C /data
    
    # Restart CMS
    docker compose -f docker-compose.hostinger.prod.yml start cms
    ```

---

## 🔄 MAINTENANCE COURANTE

### Mise à jour du Code (Deploy)

1. **Pull Git** :

    ```bash
    git pull origin main
    ```

2. **Rebuild Assets** :

    ```bash
    docker compose -f docker-compose.hostinger.prod.yml build
    ```

3. **Restart Zéro-Downtime** (Update config/images) :

    ```bash
    docker compose -f docker-compose.hostinger.prod.yml up -d --remove-orphans
    ```

### Rotation des Secrets

1. Modifier `.env`.
2. Relancer : `docker compose -f docker-compose.hostinger.prod.yml up -d`.

---

## 🔎 MONITORING & LOGS

### Vérifier les Logs

Comme le driver `json-file` est activé partout (P1 Audit), les logs sont rotatifs et n'exploseront pas le disque.

* **Tout voir** : `docker compose -f docker-compose.hostinger.prod.yml logs -f --tail=100`
* **Juste Strapi** : `docker compose -f docker-compose.hostinger.prod.yml logs -f cms`
* **Juste n8n** : `docker compose -f docker-compose.hostinger.prod.yml logs -f n8n-main`

### Santé du Système

* **Containers** : `docker compose -f docker-compose.hostinger.prod.yml ps` (Tout doit être "Up (healthy)").
* **Disque** : `df -h` (Vérifier espace libre).

---

## 📞 CONTACTS

* **Admin Système** : [Nom]
* **Niveau d'Urgence** :
  * **P0 (Site Down)** : Appel immédiat.
  * **P1 (Fonction cassée)** : SMS/WhatsApp.
  * **P2 (Bug mineur)** : Ticket/Email.

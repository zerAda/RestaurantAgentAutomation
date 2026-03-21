# Prompt pour Claude Code (Handoff)

Copiez-collez ce prompt pour continuer le travail d'upgrade CI/CD vers le niveau "Diamond Grade Pro One".

---

## CONTEXTE

Je travaille sur un projet "Diamond Grade". L'agent précédent (Antigravity) a réalisé un audit et commencé l'implémentation de la roadmap "Pro One".
Le pipeline CI/CD (`.github/workflows/cd-deploy.yml`) est déjà robuste, modulaire et sécurisé.

**Ce qui a été fait :**

1. **Modularité** : Les scripts critiques (backup, rollback, drift check) sont extraits dans `scripts/ops/`.
2. **Performance** : Cache Docker `gha` activé et Smoke Tests parallélisés (Matrix Strategy).
3. **Sécurité** : Signature des images Docker avec Cosign (Build) et vérification avant déploiement (Deploy).

## TA MISSION

Tu dois terminer l'implémentation de la Roadmap "Diamond Grade Pro One" en traitant les points suivants qui n'ont pas encore été faits :

### 1. Support Multi-Noeuds (Inventory System)

Actuellement, le déploiement est câblé pour un seul VPS (`vps-host`).

* **Objectif** : Refondre la logique pour supporter une liste d'hôtes (préparation au scaling horizontal).
* **Action** : Créer un fichier d'inventaire (ex: JSON ou TXT) ou utiliser une variable de type tableau, et boucler dessus pour les étapes de déploiement.

### 2. SBOM & SLSA Level 2+

* **Objectif** : Générer une "Software Bill of Materials" pour chaque release.
* **Action** : Ajouter une étape dans `build-push-artifacts.yml` utilisant `syft` ou `trivy` pour générer le SBOM, le signer avec Cosign, et l'attacher à l'image dans le registre GHCR.

### 3. Observabilité & Notifications Riches

* **Objectif** : Remplacer les notifications webhooks basiques par des messages riches.
* **Action** : Implémenter des notifications Slack (Block Kit) ou Discord (Embeds) qui affichent :
  * Statut du déploiement
  * Lien vers le commit / diff
  * Bouton d'action (ex: lien vers l'URL de rollback manuel)

### 4. Hardening des Inputs

* **Objectif** : Valider strictement tous les inputs des workflows.
* **Action** : Ajouter des regex ou des steps de validation pour s'assurer que `environment`, `version`, etc. sont conformes avant de lancer le moindre job.

---

**Fichiers Clés à Analyser :**

* `.github/workflows/cd-deploy.yml`
* `.github/workflows/build-push-artifacts.yml`
* `scripts/ops/*.sh`
* `project/docs/AUDIT_REPORT_AND_ROADMAP.md`

Commence par analyser l'état actuel de `cd-deploy.yml` et propose-moi un plan pour l'item #1 (Multi-Noeuds).

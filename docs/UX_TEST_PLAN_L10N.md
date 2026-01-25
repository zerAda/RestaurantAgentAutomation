# UX Test Plan — EPIC5 L10N (WhatsApp)

## Objectif
Valider que l’expérience multi-langue fonctionne **end-to-end** : script-first, boutons, darija translit, `LANG ...`, et admin templates.

## Setup
- `L10N_ENABLED=true`
- (optionnel) `L10N_STICKY_AR_ENABLED=true` + `L10N_STICKY_AR_THRESHOLD=2`
- Un compte client WhatsApp + un compte admin WhatsApp.

---

## Scénarios client (FR)
1. Envoyer `menu` → réponse FR + boutons FR.
2. Ajouter un item `P01 x2` → recap FR.
3. `checkout` → confirmation FR.
4. Cliquer `✅ Oui` → confirmation FR.

## Scénarios client (AR)
1. Envoyer `القائمة` (ou `منيو`) → réponse AR + boutons AR.
2. Mixed : `salut من فضلك` → réponse AR.
3. Cliquer un bouton après réponse AR → la langue reste AR.

## Darija translit
1. Envoyer `chno kayn` → intent MENU, réponse FR (si pas de script arabe).
2. Envoyer `kml` → intent CHECKOUT, réponse FR.
3. Avec sticky : envoyer 2 messages arabes (`مرحبا` puis `القائمة`), puis `kml` → réponse AR.

## LANG command
1. Envoyer `LANG AR` → message confirmation AR.
2. Envoyer `menu` (latin) → réponse FR (script-first) mais tracking doit utiliser AR.

## Notifications tracking (sanity)
1. Forcer un statut commande (DB) pour ce user.
2. Vérifier le message tracking correspond à la préférence `customer_preferences`.

---

## Admin WhatsApp templates
1. `!template get CORE_CLARIFY ar` → retourne contenu.
2. `!template set CORE_CLARIFY ar ...` → mise à jour.
3. Rejouer côté client (message incompris) → nouveau texte appliqué.

## Edge cases
- Message vide / emoji only → clarify.
- Message avec chiffres arabes-indic : `١٢٣` → AR.
- Très long message (>= 2000) : pas de crash.

## Critère de réussite
- Aucun “flip” de langue sur boutons.
- Aucun crash workflow.
- Templates modifiables via WhatsApp admin.
- Darija minimal fonctionne.

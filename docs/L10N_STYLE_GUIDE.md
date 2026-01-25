# Style guide — FR / AR (EPIC5)

## Objectif
Avoir des réponses :
- **courtes**, orientées action,
- cohérentes (même structure FR/AR),
- adaptées WhatsApp (mobile, peu de surcharge).

---

## FR — règles
- Tutoiement (ton friendly).
- 1 idée / 1 message (max ~4 lignes).
- Préférer verbes d’action : “Tape MENU…”, “Envoie l’ID…”.
- Emojis max 1–2 par message.

**Exemples**
- `Je n’ai pas compris. Tape MENU ou envoie un ID (ex: P01 x2).`

---

## AR — règles
- Arabe standard simple (phrases courtes, vocabulaire courant).
- Éviter formulations trop formelles.
- Conserver les IDs / codes (P01, OPT...) en latin.
- Éviter les blocs très longs (RTL + WhatsApp).

**Exemples**
- `لم أفهم. اكتب menu أو أرسل المعرف (مثال: P01 x2).`

---

## Variables (placeholders)
- Toujours utiliser `{{var}}`.
- Ne jamais concaténer des variables sans séparateur.
- Sur WhatsApp, ajouter `\n` avant un bloc optionnel (ex: `{{eta}}`).

---

## Boutons
- Titres courts (≤ 20 chars si possible).
- FR / AR : traductions fonctionnelles, pas littérales.

---

## Darija translit (latin)
- Accepter les variantes orthographiques (ex: `chno kayn`, `chnou kayen`, `wesh kayn`).
- Réponses restent **FR** sauf si message contient arabe, ou sticky AR activé.

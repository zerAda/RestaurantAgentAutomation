---
created: 2026-03-20T00:35:00.000Z
title: Resume CMS lodash/fp ESM fix — then smoke scripts
area: planning
files:
  - .planning/phases/01-cms-stability-and-base-upgrade/01-04-PLAN.md
  - project/scripts/smoke-cms-routes.sh
  - project/scripts/smoke-post-rebuild.sh
  - project/TEST_REPORT.md
---

## Problem

CMS container (current-cms-1) is crash-looping due to Node.js 20 ESM incompatibility
in `@strapi/core/dist`. Two issues found:

1. **lodash/fp directory import**: All `.mjs` files in `@strapi/core/dist` use
   `import 'lodash/fp'` or `from 'lodash/fp'` which is a directory import — banned in ESM.
   **Wrong fix tried**: `lodash/fp.js` → fails because `fp.js` has no named exports.
   **Correct fix**: `lodash/fp` → `lodash/fp/index.js` (the directory's index file).

2. **docker-entrypoint.sh printing JS source**: When using `current-cms:patched`, the
   container logs repeat JS source lines (index.js content). Needs investigation.

3. **Long build stuck at step #22**: The `chown -R strapi:strapi /app` in Dockerfile
   takes 45+ min on VPS. PIDs 2575906/2575907/2576108 may still be running.

## Patched files already on VPS (in /tmp/)

- `/tmp/strapi-core-dist/` — copy of `@strapi/core/dist` with `lodash/fp.js` fix (wrong)
- `/tmp/core-dist-final.tar` — tar of the above (wrong fix)
- `/tmp/cms-index.js` — fixed `dist/src/index.js` with `.js` extension on restaurant-menu
- `/tmp/fix-lodash.sh` — the fix script used (needs updating)

## Solution

### Step 1: Fix the lodash import correctly

```bash
# On VPS — fix ALL .mjs files to use lodash/fp/index.js instead of lodash/fp
ssh deploy@72.60.190.192
find /tmp/strapi-core-dist -name "*.mjs" ! -name "*.map" | while read f; do
  sed -i "s|'lodash/fp\.js'|'lodash/fp/index.js'|g" "$f"
  sed -i 's|"lodash/fp\.js"|"lodash/fp/index.js"|g' "$f"
done
# Verify
grep -r "lodash/fp[^/i]" /tmp/strapi-core-dist/*.mjs | head -3  # should be empty
grep "lodash/fp" /tmp/strapi-core-dist/index.mjs | head -3  # should show /index.js
```

### Step 2: Also check docker-entrypoint.sh issue

```bash
docker run --rm current-cms:patched cat /docker-entrypoint.sh 2>/dev/null | head -20
```
If it has `cat` or `source` of a JS file, that's the bug.

### Step 3: Deploy and apply fix

```bash
# Use current-cms:latest (851eb636fb22 from CI) — it's the node:20.20.0-alpine build
cd /opt/resto/current/
docker compose -f docker-compose.hostinger.prod.yml up -d --force-recreate cms

# Apply the corrected lodash fix via tar pipe
cd /tmp/strapi-core-dist && tar cf /tmp/core-dist-v2.tar .
cat /tmp/core-dist-v2.tar | docker cp - current-cms-1:/app/node_modules/@strapi/core/dist

# Also apply the restaurant-menu fix
docker cp /tmp/cms-index.js current-cms-1:/app/dist/src/index.js

docker restart current-cms-1
```

### Step 4: Wait for health, then run smoke scripts

```bash
until curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:1337/_health | grep -q "204"; do
  sleep 15; echo "waiting..."
done && echo "HEALTHY"

# Run smoke scripts
STRAPI_EMAIL=adel.zeriri@gmail.com STRAPI_PASSWORD=RestoBot2026 \
  bash /opt/resto/current/project/scripts/smoke-cms-routes.sh http://127.0.0.1:1337
STRAPI_EMAIL=adel.zeriri@gmail.com STRAPI_PASSWORD=RestoBot2026 \
  bash /opt/resto/current/project/scripts/smoke-post-rebuild.sh
```

### Step 5: Paste output → Claude updates TEST_REPORT.md → close Phase 01

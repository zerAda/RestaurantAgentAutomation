# ── Strapi 5 CMS ─────────────────────────────────────────────
# Node >= 20 required (see package.json engines)
# ─────────────────────────────────────────────────────────────
FROM node:20.20.0-alpine AS build

WORKDIR /app

# Install build deps for native modules (pg, better-sqlite3)
RUN apk add --no-cache python3 make g++

COPY package.json package-lock.json ./
RUN npm config set fetch-retries 5 && \
    npm config set fetch-retry-mintimeout 60000 && \
    npm config set fetch-retry-maxtimeout 300000 && \
    npm config set fetch-timeout 600000 && \
    npm ci --legacy-peer-deps

COPY . .

# Build-time placeholders: strapi build loads config which reads env vars.
# .dockerignore excludes .env, so we provide safe defaults for the build stage only.
# Real values are injected at runtime via environment/secrets.
ENV APP_KEYS=build-placeholder-key-1,build-placeholder-key-2
ENV ADMIN_JWT_SECRET=build-placeholder-jwt
ENV API_TOKEN_SALT=build-placeholder-salt
ENV TRANSFER_TOKEN_SALT=build-placeholder-salt
ENV ENCRYPTION_KEY=build-placeholder-encryption
ENV JWT_SECRET=build-placeholder-jwt
ENV DATABASE_CLIENT=sqlite

RUN npm run build

# ── Production stage ────────────────────────────────────────
FROM node:20.20.0-alpine

WORKDIR /app

# Install runtime deps + temporary build tools for native module compilation
RUN apk add --no-cache vips-dev python3 make g++

ENV NODE_ENV=production

COPY package.json package-lock.json ./
RUN npm config set fetch-retries 5 && \
    npm config set fetch-retry-mintimeout 60000 && \
    npm config set fetch-retry-maxtimeout 300000 && \
    npm config set fetch-timeout 600000 && \
    npm ci --omit=dev --legacy-peer-deps

# Fix: Node.js 20.20.0+ ESM/CJS interop with @strapi/core lodash imports
# (1) Named import from CJS-only lodash: convert to default import in domain/module
RUN sed -i "s/import _, { flatten } from 'lodash';/import _ from 'lodash'; const { flatten } = _;/" \
    /app/node_modules/@strapi/core/dist/domain/module/index.mjs
# (2) Create lodash/fp ESM wrapper with named exports + package.json exports map.
#     Fixes ERR_UNSUPPORTED_DIR_IMPORT and named ESM import failures across all @strapi packages
#     (290+ .mjs files do `import { xxx } from 'lodash/fp'` which fails with CJS dynamic exports).
COPY fix-lodash-fp.js /tmp/fix-lodash-fp.js
RUN node /tmp/fix-lodash-fp.js

# Remove build tools after npm ci (keep runtime-only packages)
RUN apk del python3 make g++

# Copy built admin panel + source
COPY --from=build /app/dist ./dist
COPY . .

# Remove dev artifacts carried by COPY .
RUN rm -rf node_modules/.cache src/admin/app.example.tsx

# Entrypoint reads DATABASE_PASSWORD from mounted secret file
COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh

# Security: run as non-root user
RUN addgroup -g 1001 -S strapi && \
    adduser -S strapi -u 1001 -G strapi && \
    chown -R strapi:strapi /app
USER strapi

EXPOSE 1337

ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["npm", "run", "start"]

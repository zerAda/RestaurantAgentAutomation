# ── Strapi 5 CMS ─────────────────────────────────────────────
# Node >= 20 required (see package.json engines)
# ─────────────────────────────────────────────────────────────
FROM node:20-alpine AS build

WORKDIR /app

# Install build deps for native modules (pg, better-sqlite3)
RUN apk add --no-cache python3 make g++

COPY package.json package-lock.json ./
RUN npm ci

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
FROM node:20-alpine

WORKDIR /app

RUN apk add --no-cache vips-dev

ENV NODE_ENV=production

COPY package.json package-lock.json ./
RUN npm ci --omit=dev

# Copy built admin panel + source
COPY --from=build /app/dist ./dist
COPY . .

# Remove dev artifacts carried by COPY .
RUN rm -rf node_modules/.cache src/admin/app.example.tsx

# Entrypoint reads DATABASE_PASSWORD from mounted secret file
COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh

EXPOSE 1337

ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["npm", "run", "start"]

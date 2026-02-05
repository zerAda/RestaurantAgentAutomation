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

# ── Build stage ──────────────────────────────────────────────
FROM node:20-alpine AS build

WORKDIR /app

COPY admin-dashboard/package.json admin-dashboard/package-lock.json ./
RUN npm ci

COPY admin-dashboard/ .
RUN npm run build

# ── Serve stage ─────────────────────────────────────────────
FROM nginx:1.27-alpine

COPY infra/nginx/spa-default.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/dist /usr/share/nginx/html

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]

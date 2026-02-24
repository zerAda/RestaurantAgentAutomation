# ── Build stage ──────────────────────────────────────────────
FROM node:20-alpine AS build

WORKDIR /app

ARG VITE_STRAPI_URL
ARG VITE_DOMAIN
ENV VITE_STRAPI_URL=${VITE_STRAPI_URL}
ENV VITE_DOMAIN=${VITE_DOMAIN}

COPY kiosk-app/package.json ./
RUN npm install --legacy-peer-deps

COPY kiosk-app/ .
RUN npm run build

# ── Serve stage ─────────────────────────────────────────────
FROM nginxinc/nginx-unprivileged:1.27-alpine

COPY infra/nginx/spa-default.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/dist /usr/share/nginx/html

RUN chown -R nginx:nginx /usr/share/nginx/html /var/cache/nginx /etc/nginx/conf.d && \
    touch /var/run/nginx.pid && chown nginx:nginx /var/run/nginx.pid
USER nginx

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]

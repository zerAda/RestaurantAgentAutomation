# Ralphé v3.3.0 — Full Stack Audit & Optimization

## Vision
Deep autonomous audit and optimization of the entire Ralphé restaurant automation platform: n8n workflows, Strapi CMS, Admin Dashboard, Kiosk App, infrastructure/security, LLM optimization, and cross-service interconnections.

## Core Value
Achieve Diamond Grade reliability, security, and performance across all 7 layers of the stack.

## Target Users
Restaurant operations team, developers, DevOps.

## Technical Context
- **n8n 2.9.4**: 92 workflow JSONs, queue mode, WhatsApp/IG/Messenger/TikTok
- **Strapi v4**: inventory-cms, PostgreSQL 15, content API for menu/orders/customers
- **Admin Dashboard**: React + Vite + Tailwind, TypeScript
- **Kiosk App**: React + Vite + Tailwind, TypeScript, public-facing
- **Infra**: Traefik v3.6.6, nginx 1.27, Docker Compose (12 containers), Redis 7
- **LLM**: Ollama 0.6.2 + llama3.1, Whisper STT, Darija NLP
- **VPS**: Hostinger 72.60.190.192, `deploy` user

## Key Decisions

| Decision | Source | Rationale | Outcome |
|----------|--------|-----------|---------|
| 7-phase audit structure | AI-suggested | Isolates each layer for focused analysis | Decided |
| GSD Super mode | User-requested | Full autonomy, maximum efficiency | Decided |
| Production quality bar | User | Diamond Grade security and reliability | Decided |

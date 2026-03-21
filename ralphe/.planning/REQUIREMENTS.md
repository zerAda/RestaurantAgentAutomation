# Requirements

## V1 — Must Have

| ID | Requirement | Phase | Status |
|----|-------------|-------|--------|
| R1 | Map and validate all 92 n8n workflow JSONs | 1 | Planned |
| R2 | Audit n8n payment workflows for HMAC signature verification | 1 | Planned |
| R3 | Audit Strapi API routes for auth bypass and data leakage | 2 | Planned |
| R4 | Fix Admin Dashboard TypeScript errors and auth guard gaps | 3 | Planned |
| R5 | Verify Kiosk App payment security (server-side total validation) | 4 | Planned |
| R6 | Scan for hardcoded secrets across entire codebase | 5 | Planned |
| R7 | Verify nginx security headers (HSTS, CSP, X-Frame-Options) | 5 | Planned |
| R8 | Test Darija NLP intent accuracy (target >90%) | 6 | Planned |
| R9 | Map all inter-service communication and validate Docker networking | 7 | Planned |
| R10 | Validate CI/CD pipelines (12 GitHub Actions workflows) | 7 | Planned |

## V2 — Nice to Have

| ID | Requirement | Priority | Status |
|----|-------------|----------|--------|
| R11 | LLM response caching in Redis | Medium | Backlog |
| R12 | Kiosk idle detection + screensaver | Medium | Backlog |
| R13 | Admin Dashboard real-time order updates | High | Backlog |
| R14 | Strapi query optimization (indexes, populate) | Medium | Backlog |

## Out of Scope
- New feature development — audit and hardening only
- VPS migration — current infra stays
- UI redesign — functional fixes only

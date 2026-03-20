# Roadmap

## Milestone 1: Full Stack Audit & Hardening

### Progress

| Phase | Name | Status | Plans | Date |
|-------|------|--------|-------|------|
| 1 | n8n Workflows | Planned | — | — |
| 2 | Strapi CMS | Planned | — | — |
| 3 | Admin Dashboard | Planned | — | — |
| 4 | Kiosk App | Planned | — | — |
| 5 | Infra & Security | Planned | — | — |
| 6 | LLM Optimization | Planned | — | — |
| 7 | Project Interconnections | Planned | — | — |

### Phases

#### Phase 1: n8n Workflows
**Goal:** Validate, audit, and harden all 92 n8n workflow JSONs
**Requirements:** R1, R2
- [ ] Validate all workflow JSON syntax
- [ ] Map workflow interconnections (HTTP calls between workflows)
- [ ] Scan for hardcoded secrets/credentials
- [ ] Audit payment callbacks (HMAC, amount validation)
- [ ] Check error handling and DLQ strategy
- [ ] Verify idempotency keys on inbound workflows

#### Phase 2: Strapi CMS
**Goal:** Audit Strapi API surface, auth, data leakage, and performance
**Requirements:** R3
- [ ] Map all content types and API routes
- [ ] Check auth requirements on all routes
- [ ] Scan for `populate: '*'` data leakage
- [ ] Audit CORS and middleware config
- [ ] Check bootstrap/seed security

#### Phase 3: Admin Dashboard
**Goal:** Fix TypeScript errors, verify auth guards, audit API calls
**Requirements:** R4
- [ ] Audit and fix TypeScript build errors
- [ ] Verify auth guards on all routes
- [ ] Check token storage security
- [ ] Audit Strapi v4 data mapping
- [ ] Check for XSS vectors

#### Phase 4: Kiosk App
**Goal:** Verify kiosk security, payment flow, and UX completeness
**Requirements:** R5
- [ ] Fix build errors
- [ ] Verify payment total server-side validation
- [ ] Check for exposed tokens in public bundle
- [ ] Audit Strapi v4 data format handling
- [ ] Verify kiosk mode security

#### Phase 5: Infrastructure & Security
**Goal:** Forensic security audit of all infra components
**Requirements:** R6, R7
- [ ] Scan for secrets in git history
- [ ] Audit nginx security headers
- [ ] Verify IP allowlists on private services
- [ ] Check TLS config (HSTS, ACME)
- [ ] Audit Docker networking (internal vs proxy)
- [ ] Check rate limiting

#### Phase 6: LLM Optimization
**Goal:** Optimize NLP accuracy, prompt engineering, and performance
**Requirements:** R8
- [ ] Run Darija intent test suite
- [ ] Run L10N script detection tests
- [ ] Audit system prompts (temperature, format)
- [ ] Check LLM failover strategy
- [ ] Map all Ollama-calling workflows

#### Phase 7: Project Interconnections
**Goal:** Validate cross-service communication and CI/CD
**Requirements:** R9, R10
- [ ] Validate docker-compose config
- [ ] Map service dependencies
- [ ] Check healthchecks
- [ ] Audit CI/CD pipelines
- [ ] Validate env var completeness

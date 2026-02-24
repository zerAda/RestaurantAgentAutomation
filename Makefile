# =============================================================================
# Makefile - Resto Bot (Developer Workflow)
# =============================================================================
# Mirrors CI pipeline commands for local development.
# Usage: make <target>
# =============================================================================

.PHONY: help lint test-unit test-battery test-harness smoke security up down build migrate backup preflight ci \
       setup preflight-prod deploy status logs rollback

.DEFAULT_GOAL := help

# Config
COMPOSE_PROD := docker-compose.hostinger.prod.yml

# Colors
GREEN  := \033[0;32m
YELLOW := \033[0;33m
RED    := \033[0;31m
NC     := \033[0m

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "$(GREEN)%-20s$(NC) %s\n", $$1, $$2}'

# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------
lint: ## Run all linters (bash syntax, JSON, compose validation)
	@echo "== Lint: Bash scripts =="
	@for f in scripts/*.sh; do bash -n "$$f" || exit 1; done
	@echo "All scripts valid"
	@echo ""
	@echo "== Lint: JSON workflows =="
	@for f in workflows/*.json; do python3 -m json.tool "$$f" > /dev/null || exit 1; done
	@echo "All JSON valid"

integrity: ## Run integrity gate (10-point quality check)
	@bash scripts/integrity_gate.sh

# ---------------------------------------------------------------------------
# Testing
# ---------------------------------------------------------------------------
test-unit: ## Run Python unit tests (contracts, L10N, templates)
	@pip install -q jsonschema pyyaml 2>/dev/null || true
	@python3 scripts/validate_contracts.py
	@python3 scripts/test_darja_intents.py
	@python3 scripts/test_template_render.py
	@python3 scripts/test_l10n_script_detection.py
	@echo "All unit tests passed"

test-battery: ## Run full test battery (100 tests, requires running stack)
	@bash scripts/test_battery.sh

test-harness: ## Run full CI test harness (spins up stack, runs all tests)
	@bash scripts/test_harness.sh

smoke: ## Run smoke tests against running instance (requires DOMAIN_NAME)
	@bash scripts/smoke.sh

smoke-security: ## Run security smoke tests
	@bash scripts/smoke_security.sh
	@bash scripts/smoke_security_gateway.sh

# ---------------------------------------------------------------------------
# Security
# ---------------------------------------------------------------------------
security: ## Run security checks (secrets, nginx headers, .env)
	@echo "== Security: .env not committed =="
	@test ! -f .env || (echo "ERROR: .env must not be committed" && exit 1)
	@test ! -f config/.env || (echo "ERROR: config/.env must not be committed" && exit 1)
	@echo "OK"
	@echo ""
	@echo "== Security: Nginx headers =="
	@grep -q "X-Content-Type-Options" infra/gateway/nginx.conf && echo "X-Content-Type-Options: OK"
	@grep -q "X-Frame-Options" infra/gateway/nginx.conf && echo "X-Frame-Options: OK"
	@grep -q "server_tokens off" infra/gateway/nginx.conf && echo "server_tokens off: OK"

# ---------------------------------------------------------------------------
# Docker
# ---------------------------------------------------------------------------
up: ## Start local dev environment
	@docker compose -f docker/docker-compose.yml up -d
	@echo "Dev environment started"

down: ## Stop local dev environment
	@docker compose -f docker/docker-compose.yml down
	@echo "Dev environment stopped"

up-prod: ## Start production compose (requires .env)
	@docker compose -f docker-compose.hostinger.prod.yml up -d

down-prod: ## Stop production compose
	@docker compose -f docker-compose.hostinger.prod.yml down

build: ## Build all Docker images
	@docker compose -f docker/docker-compose.yml build

# ---------------------------------------------------------------------------
# Database
# ---------------------------------------------------------------------------
migrate: ## Run database migrations
	@bash scripts/db_migrate.sh

backup: ## Create database backup
	@bash scripts/backup_postgres.sh

# ---------------------------------------------------------------------------
# Pre-flight & CI
# ---------------------------------------------------------------------------
preflight: ## Run pre-flight checks (integrity + lint + security)
	@$(MAKE) integrity
	@$(MAKE) lint
	@$(MAKE) security
	@echo ""
	@echo "== Pre-flight: All checks passed =="

ci: ## Run full CI pipeline locally (lint + unit tests + integrity + security)
	@echo "== Running local CI pipeline =="
	@$(MAKE) integrity
	@$(MAKE) lint
	@$(MAKE) test-unit
	@$(MAKE) security
	@echo ""
	@echo "== Local CI: ALL PASSED =="

# ---------------------------------------------------------------------------
# Production Deployment
# ---------------------------------------------------------------------------
setup: ## First deploy: create volumes, verify .env, fix permissions
	@echo "== Setup: Creating Docker volumes =="
	@bash scripts/setup-volumes.sh
	@echo ""
	@echo "== Setup: Checking secrets permissions =="
	@if [ -d secrets ]; then chmod 700 secrets && chmod 600 secrets/* 2>/dev/null; echo "Permissions fixed"; fi
	@echo ""
	@echo "== Setup complete =="

preflight-prod: ## Verify prod config is safe (no dev passwords, IPs restricted)
	@bash scripts/preflight-prod.sh

deploy: ## Full deploy: setup + preflight + docker compose up -d
	@echo "$(GREEN)== Deploy: Starting ==$(NC)"
	@$(MAKE) setup
	@echo ""
	@$(MAKE) preflight-prod
	@echo ""
	@echo "== Deploy: Starting services =="
	@docker compose -f $(COMPOSE_PROD) up -d --remove-orphans
	@echo ""
	@echo "$(GREEN)== Deploy: Complete ==$(NC)"
	@$(MAKE) status

status: ## Show container status + healthchecks
	@echo "== Service Status =="
	@docker compose -f $(COMPOSE_PROD) ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || \
		docker compose -f $(COMPOSE_PROD) ps
	@echo ""
	@echo "== Healthcheck Summary =="
	@docker compose -f $(COMPOSE_PROD) ps --format json 2>/dev/null | \
		python3 -c "import sys,json; [print(f'  {d[\"Name\"]:30s} {d.get(\"Health\",d.get(\"Status\",\"unknown\"))}') for line in sys.stdin for d in [json.loads(line)]]" 2>/dev/null || \
		docker compose -f $(COMPOSE_PROD) ps

logs: ## Aggregated logs from critical services (last 100 lines)
	@docker compose -f $(COMPOSE_PROD) logs --tail=100 postgres n8n-main n8n-worker gateway db-migrate

rollback: ## Rollback: stop and restart with previous images
	@echo "$(YELLOW)== Rollback: Stopping services ==$(NC)"
	@docker compose -f $(COMPOSE_PROD) down
	@echo ""
	@echo "$(YELLOW)== Rollback: Restarting with cached images ==$(NC)"
	@docker compose -f $(COMPOSE_PROD) up -d --no-build
	@echo ""
	@echo "$(GREEN)== Rollback: Complete ==$(NC)"
	@$(MAKE) status

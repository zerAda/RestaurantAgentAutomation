---
name: testing_qa
description: Test strategy with actual test infrastructure - integrity gate, test battery, k6 load tests, fixtures.
when_to_use:
  - Adding features or endpoints
  - Refactoring workflows
  - Bug fixes
  - Performance validation
  - Pre-release quality gate
---

# Testing & QA

## Test infrastructure

| Layer | Tool | Command |
|-------|------|---------|
| Integrity gate | `scripts/integrity_gate.sh` | `make integrity` |
| Unit tests | Python (contracts, Darja, templates, L10N) | `make test-unit` |
| Smoke tests | `scripts/smoke.sh` | `make smoke` |
| Security smoke | `scripts/smoke_security_gateway.sh` | `make smoke-security` |
| Full battery | `scripts/test_battery.sh` (100 tests, needs live stack) | `make test-battery` |
| CI harness | `scripts/test_harness.sh` (spins up stack + all tests) | `make test-harness` |
| E2E | `scripts/test_e2e.sh` | manual |
| Load test | `tests/k6-load-test.js` | `k6 run tests/k6-load-test.js` |

## Integrity gate checks (10 points)

1. Bash syntax check (`bash -n scripts/*.sh`)
2. Secret scan (no `CHANGE_ME` in production files)
3. Workflow JSON validation (schema + security checks)
4. JSON Schema contract tests (`scripts/validate_contracts.py`)
5. L10N tests (Darja intents, template rendering, script detection)
6. DB bootstrap ordering (FK dependency check)
7. Required files presence (migrations, scripts, docs, workflows)
8. VERSION semver format
9. Compose YAML parse
10. P0 security config validation

## Test fixtures

- Webhook payloads: `scripts/smoke/payloads/` (12 platform-specific JSON files)
- Contract schemas: `tests/contracts/` (valid/invalid JSON samples)
- SQL seeds: `tests/fixtures/` (api_clients, orders, delivery, support, l10n)
- L10N test data: `tests/darja_phrases.json`, `tests/arabic_script_cases.json`

## CI test pipeline (`.github/workflows/ci.yml`)

```
checkout -> setup python -> install deps -> integrity gate -> DB tests (with postgres service)
```

## Performance testing

- k6 script: `tests/k6-load-test.js`
- Baseline: `.github/workflows/perf-baseline.yml` (runs after deploy)
- DORA metrics: `scripts/dora_metrics.sh`
- Chaos: `scripts/chaos-monkey.sh` (manual, controlled)

## Deliverables

- Test results (which tests run, pass/fail)
- Coverage of the change (which test layers cover it)
- New test additions if testing gap identified
- Performance baseline if load-relevant change

# Claude Operating Contract — RESTO BOT

## Core principle
**Evidence-based engineering**: do not assume — read files, configs, and scripts.

## The 10-loop quality gate (internal)
Before finalizing any plan or patch, apply these loops:
1) Correctness: does it work end-to-end?
2) Contract safety: does it keep `/v1` stable?
3) Security: does it reduce attack surface? Any new leak paths?
4) Reliability: does it survive retries, timeouts, partial failures?
5) Ops: can it be deployed/rolled back quickly and safely?
6) Observability: can we detect and debug issues?
7) Data safety: are backups/restore/migrations safe?
8) Performance: any risk of queue backlog, DB lock, memory blowup?
9) DX: can a new engineer run it locally?
10) Audit readiness: can we explain & prove controls?

If any loop fails, revise until all pass.

## Required artifacts
- Repo Map (1 page max)
- Trust Boundary Diagram (ASCII ok)
- Risk Register (P0/P1/P2)
- Plan of Attack (with acceptance criteria + rollback)
- Patch diffs (atomic)
- Smoke tests (curl + expected codes)
- Runbook snippets (deploy/rollback/incident)

## “Stop rules”
Stop only when:
- P0 items are fixed or mitigated with documented compensating controls,
- and a reproducible verification path exists.

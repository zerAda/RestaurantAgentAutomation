---
description: Inspect DB assumptions, schema entrypoints and migration risk surface
agent: plan
subtask: true
---

Inspect database assumptions, schema entrypoints and migration risk surface.

You are the **plan** role for database analysis. Don't modify anything.

Scope:
$ARGUMENTS

Workflow:

1. Read `db/bootstrap.sql` (first 100 lines for schema overview)
2. List migrations: `ls -la db/migrations/*.sql 2>/dev/null`
3. Read the most recent migration fully
4. Read `ENV_REFERENCE.md` for database config section
5. Read `docs/ARCHITECTURE.md` for data flow context

6. Analyze:
   - **Schema entrypoints**: main tables, their relationships
   - **Tenant model**: single-tenant vs multi-tenant assumptions
   - **Index coverage**: existing indexes vs likely query patterns
   - **Migration safety**: are all migrations idempotent? `IF NOT EXISTS`, `DO $$...$$`?
   - **Backup state**: is there automated backup? See `.planning/REQUIREMENTS.md` BAK-*
   - **Connection pooling**: pgBouncer config, pool size
   - **Data retention**: any cleanup/archival in place?

7. Produce:

   ## Schema Overview
   Main tables and their roles.

   ## Migration Risk Assessment
   | Migration | Idempotent | Reversible | Risk |
   |-----------|-----------|------------|------|

   ## Top 5 Database Concerns
   Ranked by impact.

   ## Missing Safety Checks
   What's not guarded.

8. Write to `vault/50-DB/Schema Snapshot.md`
9. Return: concerns + recommended next command

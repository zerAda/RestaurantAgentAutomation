#!/usr/bin/env bash
# =============================================================================
# Phase 19 — local harness: boots ephemeral Postgres + ephemeral Redis (docker DOWN),
# applies the entitlement-audit seed, drives the PURE audit-hook.ts helper via node --test
# (SET->invalidateCache->GET-nil on the canonical key + the audit-row write incl. the
# product-module tenant_id=NULL path), then tears both services down on exit.
#
# Postgres runs as the system `postgres` user via /usr/lib/postgresql/16/bin (root cannot
# initdb; docker is DOWN). Redis runs from /usr/bin/redis-server on a high port. node --test
# uses --experimental-strip-types so the .ts helper imports without a separate build
# (requires Node >= 22.18; this host is Node 22.22.2).
#
# Usage: bash scripts/test-phase19.sh
# =============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

PGBIN=/usr/lib/postgresql/16/bin
RPORT=63799
PGPORT_LOCAL=55433
SEED="db/ci-fixtures/19-entitlement-audit-seed.sql"
ASSERT="db/ci-assertions/19-entitlement-audit.sql"
TESTFILE="inventory-cms/src/api/tenant-entitlement/content-types/tenant-entitlement/__tests__/audit-hook.test.mjs"

TMPPG="$(mktemp -d)"
PG_STARTED=0
REDIS_STARTED=0

cleanup() {
  set +e
  if [ "$REDIS_STARTED" = "1" ]; then
    /usr/bin/redis-cli -p "$RPORT" shutdown nosave >/dev/null 2>&1
  fi
  if [ "$PG_STARTED" = "1" ]; then
    su postgres -c "$PGBIN/pg_ctl -D $TMPPG/data stop -m fast" >/dev/null 2>&1
  fi
  rm -rf "$TMPPG" 2>/dev/null
}
trap cleanup EXIT

echo "==> Phase 19 helper harness (ephemeral PG + Redis, docker DOWN)"

# ---- Ephemeral Redis ----
echo "--> starting ephemeral redis-server on :$RPORT"
/usr/bin/redis-server --port "$RPORT" --daemonize yes --save "" --appendonly no --dir /tmp >/dev/null 2>&1
REDIS_STARTED=1
for i in $(seq 1 20); do
  if /usr/bin/redis-cli -p "$RPORT" ping 2>/dev/null | grep -q PONG; then break; fi
  sleep 0.2
done
/usr/bin/redis-cli -p "$RPORT" ping | grep -q PONG || { echo "FAIL: redis did not come up"; exit 1; }

# ---- Ephemeral Postgres (system postgres user) ----
echo "--> initializing ephemeral postgres in $TMPPG"
chown -R postgres:postgres "$TMPPG"
su postgres -c "$PGBIN/initdb -D $TMPPG/data -A trust -U postgres" >"$TMPPG/initdb.log" 2>&1
su postgres -c "$PGBIN/pg_ctl -D $TMPPG/data -o '-p $PGPORT_LOCAL -k $TMPPG' -l $TMPPG/pg.log start" >/dev/null 2>&1
PG_STARTED=1
for i in $(seq 1 30); do
  if su postgres -c "$PGBIN/pg_isready -h $TMPPG -p $PGPORT_LOCAL" >/dev/null 2>&1; then break; fi
  sleep 0.2
done

echo "--> applying seed: $SEED"
su postgres -c "$PGBIN/psql -h $TMPPG -p $PGPORT_LOCAL -U postgres -d postgres -v ON_ERROR_STOP=1 -f $REPO_ROOT/$SEED" >/dev/null

# Grant TCP access so the node-test (which connects over 127.0.0.1) can reach PG.
# pg_ctl above binds the unix socket in $TMPPG; also listen on localhost:PGPORT_LOCAL.
su postgres -c "$PGBIN/psql -h $TMPPG -p $PGPORT_LOCAL -U postgres -d postgres -c \"ALTER SYSTEM SET listen_addresses = 'localhost';\"" >/dev/null 2>&1 || true

# ---- Run the node --test helper suite ----
echo "--> running node --test (type-stripping the .ts helper)"
set +e
# Run from inside inventory-cms so Node's normal node_modules resolution finds the helper's
# imports (zod) and the test's ioredis/knex. The test path is relative to inventory-cms.
TEST_REL="src/api/tenant-entitlement/content-types/tenant-entitlement/__tests__/audit-hook.test.mjs"
( cd "$REPO_ROOT/inventory-cms" && \
  REDIS_HOST=127.0.0.1 REDIS_PORT="$RPORT" \
  PGHOST="$TMPPG" PGPORT="$PGPORT_LOCAL" PGUSER=postgres PGDATABASE=postgres \
    node --test --experimental-strip-types "$TEST_REL" )
NODE_TEST_RC=$?
set -e

# ---- Optional: SQL DO-block assertions (independent of the helper having run) ----
echo "--> running DO-block assertions: $ASSERT"
set +e
su postgres -c "$PGBIN/psql -h $TMPPG -p $PGPORT_LOCAL -U postgres -d postgres -v ON_ERROR_STOP=1 -f $REPO_ROOT/$ASSERT" 2>&1 | grep -E "NOTICE|ERROR|FAIL"
ASSERT_RC=${PIPESTATUS[0]}
set -e

echo "============================================================"
if [ "$NODE_TEST_RC" -eq 0 ] && [ "$ASSERT_RC" -eq 0 ]; then
  echo "PHASE 19 HELPER SUITE: PASS (node --test rc=$NODE_TEST_RC, assertions rc=$ASSERT_RC)"
  exit 0
else
  echo "PHASE 19 HELPER SUITE: FAIL (node --test rc=$NODE_TEST_RC, assertions rc=$ASSERT_RC)"
  exit 1
fi

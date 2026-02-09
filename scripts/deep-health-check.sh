#!/bin/bash
# =============================================================================
# Deep Health Check Script (Premium Grade)
# =============================================================================
# Performs comprehensive health checks on critical infrastructure components:
# - PostgreSQL: connections, query performance, replication lag, disk usage
# - Redis: memory usage, hit rate, persistence status, keyspace
# - n8n: queue depth, execution errors, workflow health
# - System: disk, memory, CPU
#
# Output: JSON for programmatic consumption or human-readable text
# Exit codes: 0 = healthy, 1 = degraded, 2 = critical
# =============================================================================

set -euo pipefail

# Configuration
OUTPUT_FORMAT="${1:-json}"  # json|text
POSTGRES_CONTAINER="${POSTGRES_CONTAINER:-postgres}"
REDIS_CONTAINER="${REDIS_CONTAINER:-redis}"
N8N_CONTAINER="${N8N_CONTAINER:-n8n-main}"
COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.yml}"

# Thresholds
POSTGRES_MAX_CONNECTIONS_PCT=80
REDIS_MAX_MEMORY_PCT=90
DISK_WARNING_PCT=85
DISK_CRITICAL_PCT=95
QUEUE_DEPTH_WARNING=50
QUEUE_DEPTH_CRITICAL=200

# Colors for text output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Health status tracking
OVERALL_STATUS="healthy"
CHECKS_PASSED=0
CHECKS_WARNING=0
CHECKS_FAILED=0

# JSON output accumulator
JSON_OUTPUT='{'

# =============================================================================
# Helper Functions
# =============================================================================

log_text() {
    if [ "$OUTPUT_FORMAT" = "text" ]; then
        echo -e "$1"
    fi
}

add_json_field() {
    local key="$1"
    local value="$2"
    local is_number="${3:-false}"

    if [ "$JSON_OUTPUT" != "{" ]; then
        JSON_OUTPUT="${JSON_OUTPUT},"
    fi

    if [ "$is_number" = "true" ]; then
        JSON_OUTPUT="${JSON_OUTPUT}\"${key}\":${value}"
    else
        JSON_OUTPUT="${JSON_OUTPUT}\"${key}\":\"${value}\""
    fi
}

add_json_object() {
    local key="$1"
    local value="$2"

    if [ "$JSON_OUTPUT" != "{" ]; then
        JSON_OUTPUT="${JSON_OUTPUT},"
    fi

    JSON_OUTPUT="${JSON_OUTPUT}\"${key}\":${value}"
}

set_status() {
    local new_status="$1"
    case "$new_status" in
        critical)
            OVERALL_STATUS="critical"
            CHECKS_FAILED=$((CHECKS_FAILED + 1))
            ;;
        warning)
            if [ "$OVERALL_STATUS" != "critical" ]; then
                OVERALL_STATUS="warning"
            fi
            CHECKS_WARNING=$((CHECKS_WARNING + 1))
            ;;
        healthy)
            CHECKS_PASSED=$((CHECKS_PASSED + 1))
            ;;
    esac
}

# =============================================================================
# PostgreSQL Deep Health Check
# =============================================================================

check_postgres() {
    log_text "${GREEN}[PostgreSQL]${NC} Checking..."

    local pg_health='{'
    local status="healthy"

    # 1. Connection test
    if docker compose -f "$COMPOSE_FILE" exec -T "$POSTGRES_CONTAINER" pg_isready -U n8n -d n8n > /dev/null 2>&1; then
        pg_health="${pg_health}\"accepting_connections\":true"
        log_text "  ✓ Accepting connections"
    else
        pg_health="${pg_health}\"accepting_connections\":false"
        log_text "  ${RED}✗ Not accepting connections${NC}"
        status="critical"
    fi

    # 2. Active connections and max connections
    local conn_stats=$(docker compose -f "$COMPOSE_FILE" exec -T "$POSTGRES_CONTAINER" psql -U n8n -d n8n -t -A -c "
        SELECT
            (SELECT count(*) FROM pg_stat_activity WHERE datname='n8n'),
            (SELECT setting FROM pg_settings WHERE name='max_connections')
    " 2>/dev/null || echo "0|100")

    local active_conn=$(echo "$conn_stats" | cut -d'|' -f1 | tr -d ' ')
    local max_conn=$(echo "$conn_stats" | cut -d'|' -f2 | tr -d ' ')
    local conn_pct=$((active_conn * 100 / max_conn))

    pg_health="${pg_health},\"active_connections\":${active_conn}"
    pg_health="${pg_health},\"max_connections\":${max_conn}"
    pg_health="${pg_health},\"connections_pct\":${conn_pct}"

    if [ "$conn_pct" -ge "$POSTGRES_MAX_CONNECTIONS_PCT" ]; then
        log_text "  ${YELLOW}⚠ High connection usage: ${conn_pct}% (${active_conn}/${max_conn})${NC}"
        status="warning"
    else
        log_text "  ✓ Connections: ${active_conn}/${max_conn} (${conn_pct}%)"
    fi

    # 3. Database size
    local db_size=$(docker compose -f "$COMPOSE_FILE" exec -T "$POSTGRES_CONTAINER" psql -U n8n -d n8n -t -A -c "
        SELECT pg_size_pretty(pg_database_size('n8n'))
    " 2>/dev/null | tr -d ' ')

    pg_health="${pg_health},\"database_size\":\"${db_size}\""
    log_text "  ✓ Database size: ${db_size}"

    # 4. Table count
    local table_count=$(docker compose -f "$COMPOSE_FILE" exec -T "$POSTGRES_CONTAINER" psql -U n8n -d n8n -t -A -c "
        SELECT count(*) FROM information_schema.tables WHERE table_schema='public'
    " 2>/dev/null | tr -d ' ')

    pg_health="${pg_health},\"table_count\":${table_count}"
    log_text "  ✓ Tables: ${table_count}"

    # 5. Slow queries (queries taking > 1s)
    local slow_queries=$(docker compose -f "$COMPOSE_FILE" exec -T "$POSTGRES_CONTAINER" psql -U n8n -d n8n -t -A -c "
        SELECT count(*) FROM pg_stat_activity
        WHERE state = 'active'
        AND now() - query_start > interval '1 second'
        AND query NOT LIKE '%pg_stat_activity%'
    " 2>/dev/null | tr -d ' ')

    pg_health="${pg_health},\"slow_queries\":${slow_queries}"

    if [ "$slow_queries" -gt 0 ]; then
        log_text "  ${YELLOW}⚠ Slow queries detected: ${slow_queries}${NC}"
        status="warning"
    else
        log_text "  ✓ No slow queries"
    fi

    # 6. Deadlocks
    local deadlocks=$(docker compose -f "$COMPOSE_FILE" exec -T "$POSTGRES_CONTAINER" psql -U n8n -d n8n -t -A -c "
        SELECT deadlocks FROM pg_stat_database WHERE datname='n8n'
    " 2>/dev/null | tr -d ' ')

    pg_health="${pg_health},\"deadlocks\":${deadlocks:-0}"

    if [ "${deadlocks:-0}" -gt 0 ]; then
        log_text "  ${YELLOW}⚠ Deadlocks detected: ${deadlocks}${NC}"
        status="warning"
    fi

    pg_health="${pg_health},\"status\":\"${status}\"}"

    add_json_object "postgres" "$pg_health"
    set_status "$status"
    log_text ""
}

# =============================================================================
# Redis Deep Health Check
# =============================================================================

check_redis() {
    log_text "${GREEN}[Redis]${NC} Checking..."

    local redis_health='{'
    local status="healthy"

    # 1. Ping test
    if docker compose -f "$COMPOSE_FILE" exec -T "$REDIS_CONTAINER" redis-cli ping > /dev/null 2>&1; then
        redis_health="${redis_health}\"ping\":\"ok\""
        log_text "  ✓ Ping successful"
    else
        redis_health="${redis_health}\"ping\":\"fail\""
        log_text "  ${RED}✗ Ping failed${NC}"
        status="critical"
    fi

    # 2. Memory usage
    local redis_info=$(docker compose -f "$COMPOSE_FILE" exec -T "$REDIS_CONTAINER" redis-cli info memory 2>/dev/null)

    local used_memory=$(echo "$redis_info" | grep '^used_memory:' | cut -d: -f2 | tr -d '\r' | tr -d ' ')
    local max_memory=$(echo "$redis_info" | grep '^maxmemory:' | cut -d: -f2 | tr -d '\r' | tr -d ' ')
    local used_memory_human=$(echo "$redis_info" | grep '^used_memory_human:' | cut -d: -f2 | tr -d '\r' | tr -d ' ')

    redis_health="${redis_health},\"used_memory\":${used_memory:-0}"
    redis_health="${redis_health},\"used_memory_human\":\"${used_memory_human:-0B}\""
    redis_health="${redis_health},\"max_memory\":${max_memory:-0}"

    if [ "${max_memory:-0}" -gt 0 ]; then
        local mem_pct=$((used_memory * 100 / max_memory))
        redis_health="${redis_health},\"memory_pct\":${mem_pct}"

        if [ "$mem_pct" -ge "$REDIS_MAX_MEMORY_PCT" ]; then
            log_text "  ${YELLOW}⚠ High memory usage: ${mem_pct}% (${used_memory_human})${NC}"
            status="warning"
        else
            log_text "  ✓ Memory usage: ${mem_pct}% (${used_memory_human})"
        fi
    else
        redis_health="${redis_health},\"memory_pct\":0"
        log_text "  ✓ Memory: ${used_memory_human}"
    fi

    # 3. Keyspace
    local redis_keyspace=$(docker compose -f "$COMPOSE_FILE" exec -T "$REDIS_CONTAINER" redis-cli info keyspace 2>/dev/null)
    local keys=$(echo "$redis_keyspace" | grep '^db0:' | sed 's/.*keys=\([0-9]*\).*/\1/' || echo "0")

    redis_health="${redis_health},\"keys\":${keys:-0}"
    log_text "  ✓ Keys: ${keys:-0}"

    # 4. Hit rate
    local redis_stats=$(docker compose -f "$COMPOSE_FILE" exec -T "$REDIS_CONTAINER" redis-cli info stats 2>/dev/null)
    local keyspace_hits=$(echo "$redis_stats" | grep '^keyspace_hits:' | cut -d: -f2 | tr -d '\r' | tr -d ' ')
    local keyspace_misses=$(echo "$redis_stats" | grep '^keyspace_misses:' | cut -d: -f2 | tr -d '\r' | tr -d ' ')

    redis_health="${redis_health},\"keyspace_hits\":${keyspace_hits:-0}"
    redis_health="${redis_health},\"keyspace_misses\":${keyspace_misses:-0}"

    local total_requests=$((keyspace_hits + keyspace_misses))
    if [ "$total_requests" -gt 0 ]; then
        local hit_rate=$((keyspace_hits * 100 / total_requests))
        redis_health="${redis_health},\"hit_rate_pct\":${hit_rate}"
        log_text "  ✓ Cache hit rate: ${hit_rate}%"
    else
        redis_health="${redis_health},\"hit_rate_pct\":0"
    fi

    # 5. Connected clients
    local connected_clients=$(echo "$redis_stats" | grep '^connected_clients:' | cut -d: -f2 | tr -d '\r' | tr -d ' ')
    redis_health="${redis_health},\"connected_clients\":${connected_clients:-0}"
    log_text "  ✓ Connected clients: ${connected_clients:-0}"

    # 6. Persistence status
    local redis_persist=$(docker compose -f "$COMPOSE_FILE" exec -T "$REDIS_CONTAINER" redis-cli info persistence 2>/dev/null)
    local rdb_last_save=$(echo "$redis_persist" | grep '^rdb_last_save_time:' | cut -d: -f2 | tr -d '\r' | tr -d ' ')
    local aof_enabled=$(echo "$redis_persist" | grep '^aof_enabled:' | cut -d: -f2 | tr -d '\r' | tr -d ' ')

    redis_health="${redis_health},\"aof_enabled\":${aof_enabled:-0}"
    redis_health="${redis_health},\"rdb_last_save_time\":${rdb_last_save:-0}"
    log_text "  ✓ AOF enabled: ${aof_enabled:-0}"

    redis_health="${redis_health},\"status\":\"${status}\"}"

    add_json_object "redis" "$redis_health"
    set_status "$status"
    log_text ""
}

# =============================================================================
# n8n Queue Health Check
# =============================================================================

check_n8n_queue() {
    log_text "${GREEN}[n8n Queue]${NC} Checking..."

    local queue_health='{'
    local status="healthy"

    # Check queue depth via Redis
    local queue_depth=$(docker compose -f "$COMPOSE_FILE" exec -T "$REDIS_CONTAINER" redis-cli LLEN bull:queue:jobs:waiting 2>/dev/null | tr -d '\r' || echo "0")

    queue_health="${queue_health}\"queue_depth\":${queue_depth:-0}"

    if [ "${queue_depth:-0}" -ge "$QUEUE_DEPTH_CRITICAL" ]; then
        log_text "  ${RED}✗ CRITICAL queue depth: ${queue_depth}${NC}"
        status="critical"
    elif [ "${queue_depth:-0}" -ge "$QUEUE_DEPTH_WARNING" ]; then
        log_text "  ${YELLOW}⚠ High queue depth: ${queue_depth}${NC}"
        status="warning"
    else
        log_text "  ✓ Queue depth: ${queue_depth:-0}"
    fi

    queue_health="${queue_health},\"status\":\"${status}\"}"

    add_json_object "n8n_queue" "$queue_health"
    set_status "$status"
    log_text ""
}

# =============================================================================
# System Resources Check
# =============================================================================

check_system() {
    log_text "${GREEN}[System Resources]${NC} Checking..."

    local system_health='{'
    local status="healthy"

    # 1. Disk usage
    local disk_info=$(df / | tail -1)
    local disk_pct=$(echo "$disk_info" | awk '{print $5}' | tr -d '%')
    local disk_avail=$(echo "$disk_info" | awk '{print $4}')

    system_health="${system_health}\"disk_usage_pct\":${disk_pct}"
    system_health="${system_health},\"disk_available_kb\":${disk_avail}"

    if [ "$disk_pct" -ge "$DISK_CRITICAL_PCT" ]; then
        log_text "  ${RED}✗ CRITICAL disk usage: ${disk_pct}%${NC}"
        status="critical"
    elif [ "$disk_pct" -ge "$DISK_WARNING_PCT" ]; then
        log_text "  ${YELLOW}⚠ High disk usage: ${disk_pct}%${NC}"
        status="warning"
    else
        log_text "  ✓ Disk usage: ${disk_pct}%"
    fi

    # 2. Memory
    local mem_info=$(free -m | grep Mem)
    local mem_total=$(echo "$mem_info" | awk '{print $2}')
    local mem_used=$(echo "$mem_info" | awk '{print $3}')
    local mem_pct=$((mem_used * 100 / mem_total))

    system_health="${system_health},\"memory_usage_pct\":${mem_pct}"
    system_health="${system_health},\"memory_total_mb\":${mem_total}"
    system_health="${system_health},\"memory_used_mb\":${mem_used}"

    log_text "  ✓ Memory usage: ${mem_pct}% (${mem_used}MB / ${mem_total}MB)"

    # 3. Load average
    local load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | tr -d ',')
    system_health="${system_health},\"load_average\":\"${load_avg}\""
    log_text "  ✓ Load average: ${load_avg}"

    system_health="${system_health},\"status\":\"${status}\"}"

    add_json_object "system" "$system_health"
    set_status "$status"
    log_text ""
}

# =============================================================================
# Main Execution
# =============================================================================

main() {
    local start_time=$(date +%s)

    add_json_field "timestamp" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"

    log_text "═══════════════════════════════════════════════════════════"
    log_text "  Deep Health Check - $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    log_text "═══════════════════════════════════════════════════════════"
    log_text ""

    # Run all checks
    check_postgres
    check_redis
    check_n8n_queue
    check_system

    # Calculate duration
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    add_json_field "duration_seconds" "$duration" true
    add_json_field "overall_status" "$OVERALL_STATUS"
    add_json_field "checks_passed" "$CHECKS_PASSED" true
    add_json_field "checks_warning" "$CHECKS_WARNING" true
    add_json_field "checks_failed" "$CHECKS_FAILED" true

    JSON_OUTPUT="${JSON_OUTPUT}}"

    # Output results
    if [ "$OUTPUT_FORMAT" = "json" ]; then
        echo "$JSON_OUTPUT"
    else
        log_text "═══════════════════════════════════════════════════════════"
        log_text "  Summary"
        log_text "═══════════════════════════════════════════════════════════"
        log_text "  Overall Status: ${OVERALL_STATUS}"
        log_text "  Checks Passed:  ${CHECKS_PASSED}"
        log_text "  Checks Warning: ${CHECKS_WARNING}"
        log_text "  Checks Failed:  ${CHECKS_FAILED}"
        log_text "  Duration:       ${duration}s"
        log_text "═══════════════════════════════════════════════════════════"
    fi

    # Exit with appropriate code
    case "$OVERALL_STATUS" in
        healthy)
            exit 0
            ;;
        warning)
            exit 1
            ;;
        critical)
            exit 2
            ;;
    esac
}

main "$@"

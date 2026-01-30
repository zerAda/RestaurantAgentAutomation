#!/bin/bash
# Test Redis connectivity and dedupe/rate-limit functionality
# Usage: ./scripts/test-redis.sh

set -e

REDIS_HOST="${REDIS_HOST:-redis}"
REDIS_PORT="${REDIS_PORT:-6379}"

echo "=== Redis Connectivity Test ==="
echo "Host: $REDIS_HOST:$REDIS_PORT"

# Test PING
echo -n "PING: "
docker exec -it redis redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" PING || echo "FAILED"

# Test dedupe key lifecycle
echo ""
echo "=== Dedupe Key Test ==="
TEST_KEY="ralphe:dedupe:test:$(date +%s)"
echo "Test key: $TEST_KEY"

# First SET (should succeed - new key)
echo -n "SET NX (new): "
RESULT=$(docker exec -it redis redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" SET "$TEST_KEY" "1" NX EX 60)
if [[ "$RESULT" == *"OK"* ]]; then
    echo "OK (key created)"
else
    echo "UNEXPECTED: $RESULT"
fi

# Second SET (should fail - key exists)
echo -n "SET NX (exists): "
RESULT=$(docker exec -it redis redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" SET "$TEST_KEY" "2" NX EX 60)
if [[ -z "$RESULT" || "$RESULT" == *"nil"* ]]; then
    echo "OK (correctly rejected duplicate)"
else
    echo "UNEXPECTED: $RESULT"
fi

# GET to verify
echo -n "GET: "
RESULT=$(docker exec -it redis redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" GET "$TEST_KEY")
echo "$RESULT"

# Cleanup
docker exec -it redis redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" DEL "$TEST_KEY" > /dev/null

# Test rate-limit INCR
echo ""
echo "=== Rate Limit INCR Test ==="
RL_KEY="ralphe:rl:test:$(date +%s)"
echo "Test key: $RL_KEY"

for i in 1 2 3 4 5 6 7; do
    RESULT=$(docker exec -it redis redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" INCR "$RL_KEY")
    RESULT=$(echo "$RESULT" | tr -d '\r\n')
    if [[ "$i" -le 6 ]]; then
        STATUS="ALLOWED"
    else
        STATUS="RATE_LIMITED"
    fi
    echo "INCR #$i: $RESULT ($STATUS)"
done

# Set expiry
docker exec -it redis redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" EXPIRE "$RL_KEY" 30 > /dev/null
echo "Set TTL: 30s"

# Cleanup
docker exec -it redis redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" DEL "$RL_KEY" > /dev/null

# Show current ralphe keys
echo ""
echo "=== Current ralphe:* Keys ==="
docker exec -it redis redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" --scan --pattern 'ralphe:*' | head -20

echo ""
echo "=== Redis Test Complete ==="

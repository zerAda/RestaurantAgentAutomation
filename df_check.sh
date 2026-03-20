#!/bin/bash
set -e
df -h /
echo "=== PRUNING ==="
docker system prune -f
echo "=== AFTER PRUNE ==="
df -h /

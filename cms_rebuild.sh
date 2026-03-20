#!/bin/bash
set -e
cd /opt/resto/current/
docker compose -f docker-compose.hostinger.prod.yml build cms --no-cache 2>&1 | tee /tmp/cms-build.log
docker compose -f docker-compose.hostinger.prod.yml up -d cms
docker exec current-gateway-1 nginx -s reload

until curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:1337/_health | grep -q "204"; do
  echo "Waiting for CMS... $(date)"
  sleep 15
done
echo "CMS is healthy at $(date)"

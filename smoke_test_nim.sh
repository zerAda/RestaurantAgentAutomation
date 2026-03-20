#!/bin/bash
set -e
NVIDIA_API_KEY=$(python3 -c "import json; print(json.load(open('/home/deploy/.nemoclaw/credentials.json'))['NVIDIA_API_KEY'])")
echo "=== NIM-01: Direct NVIDIA NIM API test ==="
HTTP_CODE=$(curl -s -o /tmp/nim-response.json -w "%{http_code}"   -H "Content-Type: application/json"   -H "Authorization: Bearer $NVIDIA_API_KEY"   -d '{"model":"meta/llama-3.3-70b-instruct","messages":[{"role":"user","content":"Say OK."}],"max_tokens":5}'   https://integrate.api.nvidia.com/v1/chat/completions)
if [ "$HTTP_CODE" = "200" ]; then echo "PASS: HTTP $HTTP_CODE"; else echo "FAIL: HTTP $HTTP_CODE"; cat /tmp/nim-response.json; exit 1; fi

echo "=== NIM-02: openclaw agent end-to-end ==="
RESPONSE=$(timeout 60 bash -lc "openclaw agent --message 'Say OK.'" 2>&1)
if [ $? -eq 0 ] && [ -n "$RESPONSE" ]; then echo "PASS: got response"; else echo "FAIL: $RESPONSE"; exit 1; fi

echo "=== ALL NIM SMOKE TESTS PASSED ==="

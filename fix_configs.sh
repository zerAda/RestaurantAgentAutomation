#!/bin/bash
set -e

# Backup openclaw.json
cp ~/.openclaw/openclaw.json ~/.openclaw/openclaw.json.bak

# Write openclaw.json
cat > ~/.openclaw/openclaw.json << 'EOF'
{
  "models": {
    "mode": "merge",
    "providers": {
      "nvidia": {
        "baseUrl": "https://integrate.api.nvidia.com/v1",
        "api": "openai-completions",
        "models": [
          {
            "id": "meta/llama-3.3-70b-instruct",
            "contextWindow": 131072,
            "maxTokens": 4096,
            "input": ["text"],
            "cost": { "input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0 }
          }
        ]
      }
    }
  },
  "agents": {
    "defaults": {
      "model": {
        "primary": "nvidia/meta/llama-3.3-70b-instruct"
      }
    }
  }
}
EOF

# Backup auth-profiles.json
cp ~/.openclaw/agents/main/agent/auth-profiles.json ~/.openclaw/agents/main/agent/auth-profiles.json.bak

# Read API Key
NVIDIA_API_KEY=$(python3 -c "import json; print(json.load(open('/home/deploy/.nemoclaw/credentials.json'))['NVIDIA_API_KEY'])")

# Write auth-profiles.json
cat > ~/.openclaw/agents/main/agent/auth-profiles.json << EOF
{
  "version": 1,
  "profiles": {
    "nvidia:manual": {
      "type": "api_key",
      "provider": "nvidia",
      "key": "$NVIDIA_API_KEY"
    }
  },
  "lastGood": {
    "nvidia": "nvidia:manual"
  }
}
EOF

# Validate JSON
python3 -m json.tool ~/.openclaw/openclaw.json > /dev/null && echo 'openclaw.json: valid' || echo 'openclaw.json: INVALID'
python3 -m json.tool ~/.openclaw/agents/main/agent/auth-profiles.json > /dev/null && echo 'auth-profiles.json: valid' || echo 'auth-profiles.json: INVALID'

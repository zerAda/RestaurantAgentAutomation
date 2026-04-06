#!/usr/bin/env bash
# OpenCode bootstrap for RESTO BOT
set -euo pipefail

echo "==> OpenCode setup for RESTO BOT"

# 1. Install OpenCode if missing
if ! command -v opencode >/dev/null 2>&1; then
  echo "Installing sst/opencode..."
  npm install -g opencode-ai@latest || {
    echo "npm install failed. Try: curl -fsSL https://opencode.ai/install | bash"
    exit 1
  }
fi

# 2. Check OpenRouter API key
if [ -z "${OPENROUTER_API_KEY:-}" ]; then
  echo "!! OPENROUTER_API_KEY not set."
  echo "   Get one at https://openrouter.ai/keys"
  echo "   Then: export OPENROUTER_API_KEY=sk-or-..."
fi

# 3. Bootstrap vault directories
for d in 00-Inbox 10-Queue 20-Specs 30-Architecture 40-Runbooks 50-DB 60-Observability 90-Index; do
  mkdir -p "vault/$d"
done

# 4. Install plugin deps (if package.json in .opencode/)
if [ -f ".opencode/package.json" ]; then
  (cd .opencode && npm install)
fi

echo "==> Done. Run 'opencode' to start a session."
echo "    Default agent: build (DeepSeek V3)"
echo "    Switch to planning: @plan"

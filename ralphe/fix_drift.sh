#!/bin/bash
ssh -i /c/Users/"mon pc"/.ssh/id_ed25519 -o StrictHostKeyChecking=no deploy@72.60.190.192 << 'EOF'
  cd /opt/resto/current
  VPS_VARS=$(grep -E '^[A-Z_][A-Z0-9_]*=' ../shared/.env | cut -d= -f1)
  LOCAL_VARS=$(grep -E '^[A-Z_][A-Z0-9_]*=' config/.env.example | cut -d= -f1)
  
  echo "Checking for missing variables..."
  for var in $LOCAL_VARS; do
    if ! echo "$VPS_VARS" | grep -qx "$var"; then
      echo "Adding $var to shared/.env"
      # Extract line from .env.example
      line=$(grep -E "^${var}=" config/.env.example | head -1)
      echo "$line" >> ../shared/.env
    fi
  done
  echo "Done!"
EOF

#!/bin/sh
set -e

# Read database password from Docker secret file if mounted
if [ -f "$DATABASE_PASSWORD_FILE" ]; then
  export DATABASE_PASSWORD="$(cat "$DATABASE_PASSWORD_FILE")"
fi

# FIX W3: STRAPI_SUPER_ADMIN_PASSWORD may be set to a file path (Docker secret).
# If it points to an existing file, read the actual password from that file.
if [ -n "$STRAPI_SUPER_ADMIN_PASSWORD" ] && [ -f "$STRAPI_SUPER_ADMIN_PASSWORD" ]; then
  export STRAPI_SUPER_ADMIN_PASSWORD="$(cat "$STRAPI_SUPER_ADMIN_PASSWORD")"
fi

exec "$@"

#!/bin/sh
set -e

# Read database password from Docker secret file if mounted
if [ -f "$DATABASE_PASSWORD_FILE" ]; then
  export DATABASE_PASSWORD="$(cat "$DATABASE_PASSWORD_FILE")"
fi

exec "$@"

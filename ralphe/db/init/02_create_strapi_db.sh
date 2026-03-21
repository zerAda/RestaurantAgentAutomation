#!/bin/bash
set -e

# P0-SEC-05: Database User Isolation
# This script creates a dedicated 'strapi' user with its own password from secrets.
# This prevents the CMS from accessing the 'n8n' database and vice-versa.

echo "=== Initializing Strapi Database User (Isolation) ==="

# Read Strapi DB password from secret file
if [ ! -f /run/secrets/strapi_db_password ]; then
    echo "ERROR: /run/secrets/strapi_db_password not found. Isolation failed."
    exit 1
fi

STRAPI_PASS=$(cat /run/secrets/strapi_db_password)

# 1. Ensure user 'strapi' exists and has the correct password
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    DO \$$
    BEGIN
        IF NOT EXISTS (SELECT FROM pg_catalog.pg_user WHERE usename = 'strapi') THEN
            CREATE USER strapi WITH PASSWORD '$STRAPI_PASS';
            RAISE NOTICE 'User strapi created.';
        ELSE
            ALTER USER strapi WITH PASSWORD '$STRAPI_PASS';
            RAISE NOTICE 'User strapi password updated.';
        END IF;
    END
    \$$;
EOSQL

# 2. Create database if not exists
DB_EXISTS=$(psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" -tAc "SELECT 1 FROM pg_database WHERE datname = 'strapi'")

if [ "$DB_EXISTS" != "1" ]; then
    echo "Creating database 'strapi'..."
    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" -c "CREATE DATABASE strapi OWNER strapi"
else
    echo "Database 'strapi' already exists."
    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" -c "ALTER DATABASE strapi OWNER TO strapi"
fi

# 3. Secure public schema inside 'strapi' database
echo "Securing 'strapi' database permissions..."
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "strapi" <<-EOSQL
    REVOKE ALL ON SCHEMA public FROM PUBLIC;
    GRANT ALL ON SCHEMA public TO strapi;
    ALTER SCHEMA public OWNER TO strapi;
EOSQL

echo "=== Strapi Database Initialization Complete ==="

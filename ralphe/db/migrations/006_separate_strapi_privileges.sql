-- =============================================================================
-- Migration 006: Separate Strapi User with Limited Privileges (SECURITY FIX)
-- =============================================================================
-- Problem: Strapi currently uses the same 'n8n' user which has full access
-- to all databases and tables. This violates the principle of least privilege.
--
-- Solution: Create a dedicated 'strapi' user with access ONLY to the 'strapi'
-- database and its own schema. This prevents:
-- 1. Strapi from accessing n8n's sensitive data (workflows, credentials, etc.)
-- 2. Cross-database information leakage
-- 3. Privilege escalation attacks
--
-- Execution: This migration is applied automatically by db-migrate service
-- on container startup if not already applied (tracked in schema_migrations table).
-- =============================================================================

-- Create dedicated strapi user if not exists
DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'strapi') THEN
    CREATE USER strapi WITH PASSWORD 'CHANGEME_strapi_password_12345';
    RAISE NOTICE 'User strapi created';
  ELSE
    RAISE NOTICE 'User strapi already exists';
  END IF;
END
$$;

-- Revoke all default public privileges from strapi user
REVOKE ALL ON DATABASE postgres FROM strapi;
REVOKE ALL ON SCHEMA public FROM strapi;

-- Grant connection to strapi database only
GRANT CONNECT ON DATABASE strapi TO strapi;

-- Grant schema-level privileges on strapi database
\c strapi

-- Grant usage and creation on public schema (Strapi uses this)
GRANT USAGE, CREATE ON SCHEMA public TO strapi;

-- Grant privileges on all existing tables in public schema
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO strapi;

-- Grant privileges on all existing sequences (for auto-increment IDs)
GRANT USAGE, SELECT, UPDATE ON ALL SEQUENCES IN SCHEMA public TO strapi;

-- Grant privileges on future tables (created by Strapi migrations)
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO strapi;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT, UPDATE ON SEQUENCES TO strapi;

-- Explicitly REVOKE access to n8n database
\c n8n

REVOKE CONNECT ON DATABASE n8n FROM strapi;
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM strapi;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM strapi;

-- Back to postgres database for final checks
\c postgres

-- Audit: List user privileges (PG15-compatible — information_schema.database_privileges does not exist)
SELECT
  'strapi' AS username,
  datname AS database,
  has_database_privilege('strapi', datname, 'CONNECT') AS can_connect,
  has_database_privilege('strapi', datname, 'CREATE') AS can_create
FROM pg_database
WHERE datname IN ('n8n', 'strapi', 'postgres');

COMMENT ON ROLE strapi IS 'Dedicated Strapi CMS user with limited privileges (strapi DB only)';

-- =============================================================================
-- IMPORTANT: After applying this migration, update docker-compose.hostinger.prod.yml
-- to use the strapi user for the CMS service:
--
--   cms:
--     environment:
--       - DATABASE_USERNAME=strapi
--       - DATABASE_PASSWORD_FILE=/run/secrets/strapi_db_password
--
-- And create secrets/strapi_db_password file with the password used above.
-- =============================================================================

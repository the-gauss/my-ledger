#!/usr/bin/env sh
set -eu

: "${POSTGRES_USER:?POSTGRES_USER is required}"
: "${POSTGRES_DB:?POSTGRES_DB is required}"
: "${LEDGER_INGESTION_PASSWORD:?LEDGER_INGESTION_PASSWORD is required}"
: "${LEDGER_DBT_PASSWORD:?LEDGER_DBT_PASSWORD is required}"

psql \
  --username "$POSTGRES_USER" \
  --dbname "$POSTGRES_DB" \
  --set ON_ERROR_STOP=1 \
  --set ledger_ingestion_password="$LEDGER_INGESTION_PASSWORD" \
  --set ledger_dbt_password="$LEDGER_DBT_PASSWORD" <<'SQL'
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_roles WHERE rolname = 'ledger_ingestion'
  ) THEN
    CREATE ROLE ledger_ingestion
      LOGIN
      NOSUPERUSER
      NOCREATEDB
      NOCREATEROLE
      NOINHERIT;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_roles WHERE rolname = 'ledger_dbt'
  ) THEN
    CREATE ROLE ledger_dbt
      LOGIN
      NOSUPERUSER
      NOCREATEDB
      NOCREATEROLE
      NOINHERIT;
  END IF;
END
$$;

ALTER ROLE ledger_ingestion PASSWORD :'ledger_ingestion_password';
ALTER ROLE ledger_dbt PASSWORD :'ledger_dbt_password';

REVOKE ALL ON DATABASE ledger_dwh FROM PUBLIC;
GRANT CONNECT ON DATABASE ledger_dwh TO ledger_ingestion, ledger_dbt;

REVOKE ALL ON SCHEMA public FROM PUBLIC;

CREATE SCHEMA IF NOT EXISTS raw AUTHORIZATION ledger_admin;
CREATE SCHEMA IF NOT EXISTS ingestion AUTHORIZATION ledger_admin;
CREATE SCHEMA IF NOT EXISTS analytics AUTHORIZATION ledger_dbt;

REVOKE ALL ON SCHEMA raw, ingestion, analytics FROM PUBLIC;

GRANT USAGE ON SCHEMA raw, ingestion TO ledger_ingestion;
GRANT SELECT, INSERT ON ALL TABLES IN SCHEMA raw TO ledger_ingestion;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA raw TO ledger_ingestion;

GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA ingestion TO ledger_ingestion;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA ingestion TO ledger_ingestion;

ALTER DEFAULT PRIVILEGES FOR ROLE ledger_admin IN SCHEMA raw
  GRANT SELECT, INSERT ON TABLES TO ledger_ingestion;
ALTER DEFAULT PRIVILEGES FOR ROLE ledger_admin IN SCHEMA raw
  GRANT USAGE, SELECT ON SEQUENCES TO ledger_ingestion;

ALTER DEFAULT PRIVILEGES FOR ROLE ledger_admin IN SCHEMA ingestion
  GRANT SELECT, INSERT, UPDATE ON TABLES TO ledger_ingestion;
ALTER DEFAULT PRIVILEGES FOR ROLE ledger_admin IN SCHEMA ingestion
  GRANT USAGE, SELECT ON SEQUENCES TO ledger_ingestion;

GRANT USAGE ON SCHEMA raw TO ledger_dbt;
GRANT SELECT ON ALL TABLES IN SCHEMA raw TO ledger_dbt;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA raw TO ledger_dbt;

ALTER DEFAULT PRIVILEGES FOR ROLE ledger_admin IN SCHEMA raw
  GRANT SELECT ON TABLES TO ledger_dbt;
ALTER DEFAULT PRIVILEGES FOR ROLE ledger_admin IN SCHEMA raw
  GRANT USAGE, SELECT ON SEQUENCES TO ledger_dbt;
SQL
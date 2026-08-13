# my-ledger

Local-first personal financial warehouse.

## Active components

- `apps/ingestion`: Plaid API ingestion and raw-event capture.
- `dwh`: dbt models that turn source-shaped records into warehouse tables.
- `docker-compose.yml`: local PostgreSQL through Docker Compose.

The intended data flow is:

```text
Plaid API → raw Postgres records + immutable event archive → dbt → curated warehouse tables
```

Airbyte, Airflow, and GCP are intentionally not part of the initial setup. They can be added when an operational need exists without changing the warehouse contract.

## Start locally

1. Copy `.env.example` to `.env` and replace the local database password and Plaid credentials.
2. Start PostgreSQL:

   ```sh
   docker compose up -d db
   ```

3. Install the ingestion environment:

   ```sh
   cd apps/ingestion
   uv sync
   ```

4. Install the dbt environment:

   ```sh
   cd dwh
   uv sync
   set -a; source ../../.env; set +a
   uv run dbt debug --profiles-dir .
   ```

All financial records, raw API payloads, and credentials stay out of Git.

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

## Architecture decisions

- **Local-first warehouse:** Postgres runs locally in Docker. This keeps the initial system free, private, and simple to operate.
- **Direct Plaid API ingestion:** the ingestion package owns Plaid synchronization rather than routing the primary financial source through Airbyte. This preserves complete control over cursors, transaction lifecycle changes, idempotency, and source payload retention.
- **Immutable source evidence:** the ingestion implementation will preserve original Plaid events alongside normalized records, so every derived value can be traced back to its source and the warehouse can be rebuilt when enrichment improves.
- **dbt owns transformations:** dbt will build the stable staging, core, mart, and feature layers from source-shaped raw records. Postgres remains the canonical database.
- **No historical-import work in v1:** the warehouse begins with live account sync from day one. CSV/OFX import support is a future recovery path, not current scope.
- **Minimal monorepo:** `apps/ingestion` and `dwh` exist because work begins there now. Airbyte is reserved for future commodity secondary sources; Airflow is deferred until multiple dependent jobs require orchestration; GCP is deferred until managed/cloud execution, backup, or scale provides a concrete benefit.

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

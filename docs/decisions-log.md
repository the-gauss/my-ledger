# Decisions Log

### 2026-08-16
##### SQL Users and Privileges Initialization
- For initial SQL users creation, privileges and other initial setup, we use a shell script over a .sql file so that we don't have to hardcode secrets into the file and they can be read from .gitignored .env file.
- We specifically use `sh` (the she-bang line of `infra/dwh/10-create-roles.sh`), because we're using an alpine based Postgres image, and those don't have `bash` built-in. Moreover, our `.sh` init file only contains POSIX compatible light-weight commands, so there's no reason to download additional dependency (bash).
- Also, we used `infra/` as the home of this file (instead of, say, `db/init.sql` or `dwh/init.sql` etc), because infra is the right place of setup or initialization or infrastructural orchestration, while `db/` or `dwh/` may continue to contain database or warehouse logic instead of config/setup.

### 2026-09-23
#### Migration Runner Script vs Alembic
- Plain SQL runner: fewer moving parts; migrations stay close to Postgres; ideal for raw/warehouse tables.
- Alembic: stronger migration tooling; extra framework and configuration; you would still handwrite most SQL using op.execute()

We use plain SQL migrations because Ledger is a warehouse-first project: its schema is the data contract, dbt is SQL-native, and the ingestion package currently has no SQLAlchemy models. A small runner plus hand-written SQL is more transparent and keeps DDL directly executable in psql, CI, Docker, and eventually GCP.
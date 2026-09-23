-- Source evidence is append-only. The ingestion role receives INSERT/SELECT
-- privileges only, so a normalized record can always be traced to Plaid's
-- original response.
CREATE TABLE IF NOT EXISTS raw.plaid_events (
    plaid_event_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    plaid_item_id TEXT,
    endpoint TEXT NOT NULL,
    plaid_request_id TEXT,
    payload JSONB NOT NULL,
    received_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CHECK (jsonb_typeof(payload) = 'object')
);

CREATE INDEX IF NOT EXISTS plaid_events_item_received_idx
    ON raw.plaid_events (plaid_item_id, received_at DESC);

CREATE INDEX IF NOT EXISTS plaid_events_request_id_idx
    ON raw.plaid_events (plaid_request_id)
    WHERE plaid_request_id IS NOT NULL;

-- One row per Plaid Item. access_token is intentionally excluded: keep that
-- secret in the runtime secret store rather than the warehouse.
CREATE TABLE IF NOT EXISTS ingestion.plaid_items (
    plaid_item_id TEXT PRIMARY KEY,
    institution_id TEXT,
    institution_name TEXT,
    transactions_cursor TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_successful_sync_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS raw.accounts (
    plaid_account_id TEXT PRIMARY KEY,
    plaid_item_id TEXT NOT NULL REFERENCES ingestion.plaid_items (plaid_item_id),
    name TEXT NOT NULL,
    official_name TEXT,
    account_type TEXT NOT NULL,
    account_subtype TEXT,
    mask TEXT,
    iso_currency_code TEXT,
    unofficial_currency_code TEXT,
    current_balance NUMERIC(18, 2),
    available_balance NUMERIC(18, 2),
    credit_limit NUMERIC(18, 2),
    raw_payload JSONB NOT NULL,
    source_event_id BIGINT NOT NULL REFERENCES raw.plaid_events (plaid_event_id),
    first_seen_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_seen_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CHECK (jsonb_typeof(raw_payload) = 'object'),
    CHECK (iso_currency_code IS NULL OR unofficial_currency_code IS NULL)
);

CREATE INDEX IF NOT EXISTS accounts_item_idx
    ON raw.accounts (plaid_item_id);

CREATE TABLE IF NOT EXISTS raw.transactions (
    plaid_transaction_id TEXT PRIMARY KEY,
    plaid_account_id TEXT NOT NULL REFERENCES raw.accounts (plaid_account_id),
    plaid_item_id TEXT NOT NULL REFERENCES ingestion.plaid_items (plaid_item_id),
    pending_transaction_id TEXT,
    account_owner TEXT,
    transaction_date DATE NOT NULL,
    authorized_date DATE,
    authorized_datetime TIMESTAMPTZ,
    datetime TIMESTAMPTZ,
    amount NUMERIC(18, 2) NOT NULL,
    iso_currency_code TEXT,
    unofficial_currency_code TEXT,
    name TEXT NOT NULL,
    merchant_name TEXT,
    merchant_entity_id TEXT,
    pending BOOLEAN NOT NULL,
    payment_channel TEXT,
    transaction_code TEXT,
    personal_finance_category JSONB,
    location JSONB,
    raw_payload JSONB NOT NULL,
    source_event_id BIGINT NOT NULL REFERENCES raw.plaid_events (plaid_event_id),
    first_seen_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_seen_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    removed_at TIMESTAMPTZ,
    CHECK (jsonb_typeof(raw_payload) = 'object'),
    CHECK (
        personal_finance_category IS NULL
        OR jsonb_typeof(personal_finance_category) = 'object'
    ),
    CHECK (location IS NULL OR jsonb_typeof(location) = 'object'),
    CHECK (iso_currency_code IS NULL OR unofficial_currency_code IS NULL)
);

CREATE INDEX IF NOT EXISTS transactions_account_date_idx
    ON raw.transactions (plaid_account_id, transaction_date DESC);

CREATE INDEX IF NOT EXISTS transactions_item_date_idx
    ON raw.transactions (plaid_item_id, transaction_date DESC);

CREATE INDEX IF NOT EXISTS transactions_pending_transaction_idx
    ON raw.transactions (pending_transaction_id)
    WHERE pending_transaction_id IS NOT NULL;

-- Accounts and transactions represent the latest source state and must be
-- updatable for Plaid's modified records. Events remain insert-only.
GRANT UPDATE ON raw.accounts, raw.transactions TO ledger_ingestion;

-- A run is an audit record; the durable cursor is updated on plaid_items only
-- after all source writes in that sync transaction have succeeded.
CREATE TABLE IF NOT EXISTS ingestion.sync_runs (
    sync_run_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    plaid_item_id TEXT NOT NULL REFERENCES ingestion.plaid_items (plaid_item_id),
    started_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    completed_at TIMESTAMPTZ,
    status TEXT NOT NULL DEFAULT 'running',
    starting_cursor TEXT,
    ending_cursor TEXT,
    added_count INTEGER NOT NULL DEFAULT 0 CHECK (added_count >= 0),
    modified_count INTEGER NOT NULL DEFAULT 0 CHECK (modified_count >= 0),
    removed_count INTEGER NOT NULL DEFAULT 0 CHECK (removed_count >= 0),
    plaid_request_id TEXT,
    error_code TEXT,
    error_message TEXT,
    CHECK (status IN ('running', 'succeeded', 'failed')),
    CHECK (
        (status = 'running' AND completed_at IS NULL)
        OR (status IN ('succeeded', 'failed') AND completed_at IS NOT NULL)
    ),
    CHECK (status <> 'succeeded' OR ending_cursor IS NOT NULL)
);

CREATE INDEX IF NOT EXISTS sync_runs_item_started_idx
    ON ingestion.sync_runs (plaid_item_id, started_at DESC);

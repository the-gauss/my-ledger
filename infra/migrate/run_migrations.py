#!/usr/bin/env python3
"""Apply immutable SQL migrations to the my-ledger warehouse.

Migration files live in ``dwh/migrations/`` and must be named:

    NNN_description.sql

The runner records each successfully committed migration in
``ingestion.schema_migrations``. It is safe to run repeatedly: only files not
already recorded are applied. A checksum prevents an already-applied migration
from being changed silently.

Run locally using the ingestion environment:

    DATABASE_URL=postgresql://... uv run --directory apps/ingestion \\
        python infra/migrate/run_migrations.py

This runner deliberately does not create database roles or schemas. Those are
first-database bootstrap concerns handled by ``infra/dwh/10-create-roles.sh``.
"""
from __future__ import annotations

import hashlib
import os
import re
import sys
from pathlib import Path

import psycopg


MIGRATION_FILENAME = re.compile(r"^\d{3,8}(?:_\d{2})?_[a-z0-9_]+\.sql$")    # validates migration filenames, to reject badly named or non-SQL files
ADVISORY_LOCK_NAME = "my-ledger:warehouse-migrations"

CREATE_TRACKING_TABLE = """
CREATE TABLE IF NOT EXISTS ingestion.schema_migrations (
    filename TEXT PRIMARY KEY,
    checksum TEXT NOT NULL,
    applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
"""


def migrations_dir() -> Path:
    """Resolve the repository or container location of SQL migrations."""
    configured_path = os.environ.get("MIGRATIONS_DIR")
    if configured_path:
        return Path(configured_path).expanduser().resolve() #.expanduser() converts "~" into fully qualified name, while .resolve() resolves separators, resulting in an absolute path

    script_path = Path(__file__).resolve()
    candidates = [
        # Repository layout: infra/migrate/run_migrations.py and dwh/migrations/.
        script_path.parents[2] / "dwh" / "migrations",      # [2] means go back 3 folders, i.e., project root
        # Optional container layout: /app/run_migrations.py and /app/migrations/.
        script_path.parent / "migrations",
    ]
    return next((path for path in candidates if path.is_dir()), candidates[0])  # next() returns the first item from the iterator (arg 1), if none, returns candidates[0] (arg2)


def migration_files() -> list[Path]:
    """Return validated migration files in their deterministic apply order."""
    directory = migrations_dir()
    if not directory.is_dir():
        raise RuntimeError(f"Migration directory does not exist: {directory}")

    files = sorted(directory.glob("*.sql"))     # .glob() returns filesystem path matching a pattern
    invalid = [path.name for path in files if not MIGRATION_FILENAME.fullmatch(path.name)]
    if invalid:
        raise RuntimeError(
            "Invalid migration filename(s): "
            + ", ".join(invalid)
            + ". Expected NNN_description.sql (for example, 001_raw_plaid.sql)."
        )
    return files


def checksum(path: Path) -> str:
    """Return the SHA-256 digest of a migration's exact UTF-8 source bytes."""
    return hashlib.sha256(path.read_bytes()).hexdigest()


def database_url() -> str:
    """Read the libpq-compatible connection URL required by the runner."""
    value = os.environ.get("DATABASE_URL", "").strip()
    if not value:
        raise RuntimeError("DATABASE_URL environment variable is not set.")

    # The migration runner is synchronous. Accept a common application URL
    # spelling while passing a libpq-compatible scheme to psycopg.
    return value.replace("postgresql+asyncpg://", "postgresql://", 1)


def main() -> None:
    files = migration_files()

    try:
        conn = psycopg.connect(database_url())
    except psycopg.Error as exc:
        raise RuntimeError(f"Could not connect to PostgreSQL: {exc}") from exc

    try:
        with conn.cursor() as cur:
            cur.execute(CREATE_TRACKING_TABLE)
        conn.commit()

        # A session-level lock survives per-migration commits and is released
        # automatically if this process exits or the connection is lost.
        with conn.cursor() as cur:
            cur.execute("SELECT pg_advisory_lock(hashtext(%s))", (ADVISORY_LOCK_NAME,))

        with conn.cursor() as cur:
            cur.execute("SELECT filename, checksum FROM ingestion.schema_migrations")
            applied = dict(cur.fetchall())

        current_names = {path.name for path in files}
        missing_from_repo = sorted(set(applied) - current_names)    # this is to ensure all migrations, in sequence, are present. If history is missing, must not apply migrations because all migrations depend on all previous ones.
        if missing_from_repo:
            raise RuntimeError(
                "Applied migration file(s) are missing from this checkout: "
                + ", ".join(missing_from_repo)
            )

        pending: list[tuple[Path, str]] = []
        for path in files:
            digest = checksum(path)
            recorded_digest = applied.get(path.name)
            if recorded_digest is None:
                pending.append((path, digest))
            elif recorded_digest != digest:
                raise RuntimeError(
                    f"Applied migration has been modified: {path.name}. "
                    "Create a new corrective migration instead."
                )

        if not pending:
            print("No pending migrations.")
            return

        for path, digest in pending:
            print(f"Applying {path.name} ...", end=" ", flush=True)
            sql = path.read_text(encoding="utf-8")
            if not sql.strip():
                raise RuntimeError(f"Migration is empty: {path.name}")

            try:
                with conn.cursor() as cur:
                    cur.execute(sql)
                    cur.execute(
                        """
                        INSERT INTO ingestion.schema_migrations (filename, checksum)
                        VALUES (%s, %s)
                        """,
                        (path.name, digest),
                    )
                conn.commit()
            except psycopg.Error:
                conn.rollback()
                raise

            print("done.")

        print(f"Applied {len(pending)} migration(s).")
    finally:
        conn.close()


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, psycopg.Error) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        sys.exit(1)

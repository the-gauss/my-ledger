# Ingestion

This package will own direct Plaid API synchronization, idempotent database writes, and immutable raw-event archival.

It deliberately contains no scheduling or orchestration framework. The first implementation should expose small, independently runnable commands that an orchestrator can invoke later.

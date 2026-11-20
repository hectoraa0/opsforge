# Architecture decisions (ADR log)

## ADR-001 — Small real service instead of an empty demo
**Decision:** incident-management API with persisted data. This demonstrates deployment, healthchecks, database migrations, HTTP metrics and integration testing. A service with actual behavior is more persuasive than a single static page.

## ADR-002 — PostgreSQL with Alembic
**Decision:** PostgreSQL in Compose and migration scripts. `create_all()` is used only by isolated unit tests; production schema changes require explicit migrations.

## ADR-003 — Keep host ports loopback-only
**Decision:** bind HTTP host ports to `127.0.0.1`. There is no authentication or TLS in M1. This is a lab and must not be placed directly on the public internet.

## ADR-004 — Observability is opt-in
**Decision:** Prometheus and Grafana are behind Compose profile `observability`, to reduce RAM pressure on a student laptop. Request metrics are instrumented inside the API from M1 onward.

## ADR-005 — Separate unit vs integration tests
**Decision:** fast API unit tests use SQLite; a Docker-backed smoke test exercises real PostgreSQL as part of CI. This deliberately does not claim complete PostgreSQL behavioral equivalence.

## ADR-006 — Progressively add platform tools
**Decision:** Kubernetes, Terraform, alerting and deployment are separate milestones. Avoid meaningless complexity and verify each stage before proceeding.

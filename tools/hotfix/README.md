# LifeMate one-shot product patches

The scripts in this directory were used to materialize the women-calendar pilot,
caregiver-permission, and medication-notification source changes on
`feat/women-calendar-care-access-notifications`.

The committed application, Edge, migration, and integration-test files are now
the source of truth. The `women-calendar-pilot-audit` workflow checks stable
materialization markers before invoking the original generators, so repeated CI
runs remain deterministic and do not try to reapply formatting-sensitive
one-shot replacements.

Small hardening scripts may still run after the guard when a pending safety fix
has not yet been materialized. Every resulting product change must pass the full
Shared, WellMate, CareMate, Edge, PostgreSQL isolation, privacy, and notification
gates before the workflow is allowed to commit it.

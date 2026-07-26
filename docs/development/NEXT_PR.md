# Next pull request

## v0.2 — Care relationships

The next production-code pull request must implement:
- expiring, single-use caregiver invitations
- patient-caregiver relationships without global patient/caregiver roles
- explicit consent
- acceptance, listing, and revocation
- participant-only authorization
- audit records for every state transition
- PostgreSQL migration and snapshot consistency
- unit and integration tests for expiry, duplicate invitation, self-invite, cross-user isolation, and immediate revocation

Non-goals: medications, notifications, Flutter integration, SMS, payments, and AI.

# Provider backup / PITR recovery gate

Parent: Foundation #211.

This gate is deliberately separate from the repository logical restore drill. A green `postgres-restore-drill` proves that the canonical schema, data, grants and restricted roles can be reconstructed from a logical archive in clean PostgreSQL. It does **not** prove that the active hosted project has a current provider backup, Point-in-Time Recovery (PITR), a particular retention window, or a tested provider restore path.

## Closed-beta recovery objectives

For the initial controlled beta:

- **RPO target:** 24 hours or better.
- **RTO target:** 4 hours or better.
- **Recovery owner:** repository/project owner until an explicit operations owner is assigned.
- **Safety:** never run a destructive restore/failover experiment against the live production database or real patient data.

These are launch objectives, not claims about any selected provider plan. If the selected provider plan cannot meet them, the limitation and compensating procedure require an explicit release decision before real-family onboarding.

## Current compensating path

The current hosted database plan does not provide the managed-backup/PITR acceptance path required by this gate. For the current Foundation/beta phase, the founder has explicitly selected a **provider-independent encrypted workstation logical backup** as the compensating path under #226.

The source contract is implemented under #227/#228/#229/#230 and documented in `docs/operations/WORKSTATION_BACKUP.md`:

- standard PostgreSQL `pg_dump`/`pg_restore`, not a provider CLI or provider backup format;
- explicit LifeMate-owned schema allowlist;
- a read-only, non-superuser backup role with narrowly scoped RLS bypass for complete dumps;
- direct streaming from `pg_dump` into `age` ciphertext with no normal plaintext backup artifact;
- daily Windows workstation scheduling, retention and ciphertext freshness/integrity checks;
- private recovery key and database credential kept outside Git, PostgreSQL and task arguments;
- isolated/non-production restore verification before recovery evidence can pass.

This source implementation does not itself prove that a real workstation backup exists. #226 remains OPEN until the founder workstation is configured, a fresh encrypted backup is produced, and an isolated restore/security exercise is measured against the RPO/RTO targets.

## Evidence required from the active provider

Record non-secret evidence in #211 for whichever provider is active at release time:

1. selected provider/plan or tier relevant to backup capability;
2. whether managed backups/snapshots are enabled;
3. actual backup schedule/frequency;
4. actual retention window;
5. whether PITR is available/enabled and its recovery granularity/window;
6. how a restore is initiated and whether it can restore/clone to an isolated target;
7. provider limitations that can extend RTO or lose data beyond the RPO target;
8. evidence date and owner who verified the configuration.

If the approved workstation compensating path is the actual beta recovery mechanism, record the provider limitation plus the workstation evidence instead of inventing provider backup/PITR claims.

Do not put database passwords, service-role keys, provider access tokens, user identifiers or health data into the evidence.

## Provider-safe recovery exercise

Where the plan/provider supports it, exercise recovery to a disposable/non-production target. Never overwrite production as a test.

The restored target must be verified with synthetic fixtures only:

- canonical migration/schema state is present;
- `Account/AppUser -> AccountPersonLink -> Person` compatibility invariants are preserved during the current migration period;
- restricted Edge/worker database roles are non-superuser and do not regain `BYPASSRLS`;
- healthcare authorization still fails closed for an unrelated user;
- patient/caregiver relationship, consent/access-grant and revocation semantics remain intact;
- treatment/adherence/health ownership relationships are internally consistent;
- retention/account-deletion state is internally consistent;
- the current identity-link token schema/key-version references required by #217 are recoverable **without** placing the external protective key in the database backup.

If a provider clone/restore is unavailable on the selected plan, document that limitation and prove the compensating logical-backup path on an isolated provider-safe target. Do not rename that evidence PITR.

## Configuration and key recovery

Database recovery alone is not enough. Maintain recoverability for:

- canonical migrations and application source in Git;
- Edge/worker deployment configuration;
- restricted runtime database credentials through provider secret rotation/reprovisioning;
- Android founder signing backup/ownership under #212;
- identity-link key **reference/version** under #217.

The actual `LIFEMATE_IDENTITY_LINK_KEY` must remain outside PostgreSQL and database backup artifacts. Its encrypted operational backup and rotation/recovery ownership are separate from database data. A database snapshot containing the protective key would defeat the database-only breach boundary.

## Incident decision sequence

1. Stop or constrain writes if continued writes risk compounding corruption.
2. Identify the last known good release/migration and incident start window.
3. Decide forward-fix vs database recovery; prefer a reversible forward fix when integrity permits.
4. Restore/clone to an isolated target first.
5. Run security/integrity verification on the isolated target.
6. Record expected data-loss window vs the RPO target and elapsed recovery time vs the RTO target.
7. Only after verification, perform the reviewed production recovery action.
8. Re-run exact-main health/readiness, unauthenticated 401 and patient/caregiver/unrelated authorization checks.
9. Record incident evidence without PHI/PII and create follow-up tasks for every gap.

## Evidence template

Use this shape in #211 or a private operational record referenced from #211:

```text
Verified at UTC:
Verified by:
Provider/project:
Plan/tier:
Managed backup enabled: yes/no
Approved compensating path (if any):
Backup frequency:
Retention window:
PITR available/enabled: yes/no
PITR window/granularity:
Recovery/clone target:
Exercise used synthetic data only: yes/no
Logical restore workflow run:
Workstation encrypted backup evidence (if selected):
Restricted-role/security checks: pass/fail
Identity-link external key remained outside DB backup: yes/no
Measured recovery duration:
Measured/expected data-loss window:
RPO target <= 24h: pass/fail
RTO target <= 4h: pass/fail
Known limitations:
Follow-up issues:
```

## Closure rule

#211 remains OPEN until provider capability/retention are evidenced and a provider-supported or explicitly approved compensating recovery path has been exercised safely. Source documentation and CI logical restoreability are necessary but not sufficient.
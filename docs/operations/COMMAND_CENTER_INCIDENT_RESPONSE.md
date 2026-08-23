# LifeMate Command Center Incident Response Runbook

Status: source runbook for Closed Beta operations. This document does **not** prove that a production incident drill, provider backup restore, session revocation, or staff-disable workflow has been executed successfully.

## Scope

Use this runbook for incidents involving the LifeMate Command Center, `lifemate-admin-api`, workforce authentication, Admin authorization, administrative audit evidence, or the Vercel-hosted Admin frontend.

The Command Center is an administrative control plane. Authentication success alone is not authorization: an active `admin.members` membership, an effective capability, and the required AAL level still apply. Founder or Super Admin status never implies raw-health or Women Health access.

## Operating principles

1. Protect people and data before restoring convenience.
2. Preserve evidence before changing or deleting anything.
3. Prefer reversible containment over destructive recovery.
4. Never paste tokens, passwords, OTPs, database URLs, health payloads, or PII into GitHub, chat, tickets, screenshots, or this runbook.
5. Do not use Admin staging as a production restore source unless drift has been independently measured and approved.
6. Do not bypass the Admin API with direct browser/database access during an incident.
7. If an operation is not backed by a canonical server contract, record it as unavailable rather than improvising a privileged shortcut.

## Severity

| Severity | Example | Initial response |
| --- | --- | --- |
| SEV-1 | confirmed privileged-account takeover, leaked production secret, unauthorized Admin mutation, suspected raw-health exposure, audit integrity compromise | contain immediately; freeze risky Admin changes; preserve evidence; Founder/security lead coordinates |
| SEV-2 | Admin API unavailable, authorization failures affecting legitimate operators, repeated suspicious denied actions, production deployment regression without confirmed data exposure | restrict affected workflow; investigate logs/audit/deployment evidence; prepare rollback if verified safe |
| SEV-3 | isolated UI failure, stale non-sensitive management view, non-production preview issue | track and repair through normal PR/CI workflow |

When impact is uncertain, classify one level higher until evidence supports lowering it.

## First 15-minute checklist

- Record UTC start time, reporter, affected surface, and a short symptom description without sensitive payloads.
- Capture immutable references where available: deployment ID/commit SHA, correlation ID, audit event IDs, Supabase function version, and relevant CI run IDs.
- Check whether the incident is limited to frontend, Admin API, Auth, database access, or multiple layers.
- Stop new high-risk administrative changes if integrity is uncertain. Do not disable the entire LifeMate healthcare runtime unless evidence shows it is required.
- Preserve current audit/deployment/log evidence before rotating or revoking anything.
- Do not redeploy, migrate, restore, or change production authorization merely to “see if it fixes it.”

## Compromised Admin account

### What can be done immediately without inventing a new product path

- Treat the identity as untrusted and preserve its recent Admin audit trail, relevant Auth/security events, correlation IDs, and deployment evidence.
- Determine whether suspicious actions were `Allowed`, `Denied`, `Succeeded`, or `Failed`; do not infer impact from login evidence alone.
- Review the account's current Admin membership and effective roles through approved read paths.
- Identify any affected secrets or provider credentials independently of the user's browser session.

### Containment actions that require a canonical capability

Disabling/re-enabling staff membership, role revoke, force re-auth, and session revocation must use reviewed server-side workflows. If the current production contract does not support one of these actions, mark that containment action **Unavailable / Contract Missing** and escalate to an owner-approved operational procedure. Do not write directly to `admin.members`, `admin.member_roles`, `auth.sessions`, or other privileged tables from the browser or an ad-hoc script.

Issues #44/#111 in `Hamrez95/lifemate-admin` own the normal staff-management workflow. Production session/recovery hardening remains part of #113/#115/#116. Their source status must be re-verified before using them during an incident.

## Suspected authorization or data-exposure incident

1. Verify the exact request path, actor account, permission checked, AAL level, resource type, result, correlation ID, and timestamp from privacy-safe evidence.
2. Determine whether the browser received data it should not have received. UI visibility alone is not proof of server authorization.
3. Confirm that ordinary Admin runtime did not gain unexpected grants to raw `lifemate` health tables.
4. For any suspected elevated-health exposure, verify an exact subject/scope/TTL grant. Founder/Super Admin is not a bypass.
5. Preserve evidence and stop the affected operation. Do not implement emergency `service_role`, `SECURITY DEFINER`, broad RLS, or direct-table shortcuts.
6. If the incident suggests a schema/grant drift, compare source migrations and live grants read-only before proposing remediation.

## Audit evidence

`admin.audit_events` is designed as append-oriented evidence. The canonical foundation grants the normal Admin runtime SELECT/INSERT and deliberately withholds UPDATE/DELETE/TRUNCATE. Application code must not store raw health payloads, credentials, or secrets in audit metadata.

### Retention status

A final legal/product retention duration for Command Center audit evidence is **Not Yet Defined / Not Implemented** in the currently verified canonical contract. Until an approved retention policy and export/archive mechanism exist:

- do not create an ad-hoc deletion job;
- do not claim a specific retention period;
- preserve incident-relevant evidence;
- track the policy decision and implementation under operational governance before automating expiry.

## Backup and restore

Use `docs/operations/BACKUP_RESTORE_MONITORING.md` as the canonical source runbook for backup/restore mechanics and evidence expectations.

Current source evidence includes a least-privilege portable backup path and a disposable PostgreSQL restore drill. This is **not equivalent** to proof that Supabase provider backups/PITR are enabled or that a production restore has been successfully performed. Never promote Admin staging as a production restore source based only on table similarity.

Any real production restore, PITR, database replacement, or destructive rollback requires explicit production approval and a verified restore point.

## Frontend / Vercel incident

- Identify the exact Git commit and deployment ID serving production; do not assume `main` equals the live deployment.
- Check runtime error clusters and deployment state before changing code.
- A source merge is not deployment evidence.
- Roll back only to a deployment whose application/backend contracts are compatible with the current canonical database/API state.
- Never expose server secrets through `NEXT_PUBLIC_*` as a recovery shortcut.

## Admin API / Supabase incident

- Record the active Edge Function version and relevant release/source SHA if available.
- Check health/read-only evidence first.
- Compare migration history, grants, exposed schemas, RLS posture, and runtime identity read-only before proposing DDL.
- Do not enable RLS blindly on a live table without understanding existing grants/policies and runtime dependencies.
- Do not apply a migration or redeploy an Edge Function as part of diagnosis unless production mutation has been explicitly approved.

## Recovery exit criteria

Do not declare recovery complete until applicable evidence exists for all of the following:

- unauthorized access path is contained or proven not to exist;
- required legitimate Admin path works with correct membership/capability/AAL enforcement;
- denied-path checks still fail closed;
- audit evidence remains readable and privacy-safe;
- production deployment/function/database versions are explicitly recorded;
- no new secret or direct-database shortcut was introduced;
- follow-up risks and missing contracts are captured as issues rather than hidden by manual workarounds.

## Post-incident review template

- Incident ID / severity:
- UTC start / detection / containment / recovery times:
- User-visible impact:
- Data/security impact (confirmed vs suspected):
- Affected deployment/function/schema versions:
- Trigger/root cause:
- Why existing controls did or did not contain it:
- Audit/correlation evidence references:
- Recovery actions and approvals:
- What was intentionally **not** done due to safety/contract boundaries:
- Follow-up GitHub issues with owners/priorities:
- Required runbook/test/monitoring changes:

Do not include credentials, raw tokens, OTPs, health payloads, or unnecessary PII in the postmortem.

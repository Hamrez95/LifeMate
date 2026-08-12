# LifeMate Command Center threat model

## Assets

- administrator authentication sessions and MFA state;
- admin membership, roles and capability assignments;
- user identity/contact data visible to authorized support/admin workflows;
- commercial, finance, marketing and operational management data;
- administrative audit evidence;
- elevated-access requests and approval history;
- future social, payment and AI integration secrets stored server-side;
- health and highly-sensitive women-health data that must remain denied by default.

## Actors

Founder, Super Admin, Product, Support, Marketing, Finance, Technical and Security staff; compromised staff account; malicious or careless internal operator; unauthenticated attacker; compromised browser/device; attacker with leaked API credentials; compromised external integration; and future AI/tooling processes.

## Trust boundaries

```text
Browser -> Supabase Auth -> lifemate-admin-api -> lifemate_admin_runtime -> allowed DB surfaces
                                      |
                                      +-> future approved external adapters

Healthcare data -> separate authorization / break-glass boundary -> limited response only
```

## Primary abuse cases and controls

| Threat | Required control |
|---|---|
| stolen admin password/session | mandatory AAL2/MFA; short/revocable sessions; server-side membership check |
| hidden-menu authorization bypass | API capability checks; denial tests for unrelated roles |
| Support user reads Finance/payroll | capability-scoped endpoints; server-side `finance.read`; denial tests |
| Founder role silently implies raw health access | elevated health permissions are non-role-assignable; subject/time-bound break-glass |
| browser directly reads production health tables | no DB/service-role credentials in browser; admin runtime has no health-schema privilege |
| Admin API SQL injection / arbitrary querying | parameterized queries; bounded validation; no arbitrary SQL endpoint |
| compromised Admin API erases its audit trail | dedicated append-oriented audit table; runtime has no UPDATE/DELETE/TRUNCATE audit privilege |
| forged/replayed high-risk mutation | authenticated actor; idempotency key; request hash/status persistence as mutations are added |
| CSRF/cross-origin browser abuse | explicit origin allowlist plus bearer-session validation; avoid credential-bearing wildcard CORS |
| MFA UI exists but backend accepts AAL1 | Admin API rejects authenticated Command Center routes below AAL2 |
| break-glass becomes permanent access | exact subject + exact capability + approval + expiration + revocation + audit |
| women-health note leakage | separate elevated capability and dedicated response mapping; never include private notes by default |
| AI bypasses operator RBAC | tool-by-tool authorization using current admin permissions; AI starts read-only |
| AI receives raw medical/private notes | business/aggregate tools only by default; sensitive AI use requires a separate privacy/security review |
| social/payment token exposure | server-side secret storage; adapter interfaces; never return provider secrets to browser |
| preview environment exposes production data | environment isolation; synthetic/approved preview data; no unrestricted production credentials |

## Required security regression coverage

Each new restricted Admin API endpoint should include positive and negative role cases. At minimum preserve these invariants:

- Support cannot read Finance.
- Marketing cannot read payroll/finance unless explicitly granted.
- Finance cannot read raw health information by virtue of Finance role.
- Founder/Super Admin cannot receive raw health access from ordinary role membership.
- Admin runtime cannot directly query health compatibility tables.
- Admin audit history cannot be modified or erased by the normal Admin API database identity.
- AAL1 sessions cannot use authenticated Command Center routes.
- expired/revoked memberships and elevated-access requests fail closed.

## Logging policy

Log correlation IDs, operation names, coarse resource identifiers, results and privacy-safe error codes. Do not log authorization headers, JWTs, refresh tokens, passwords, OTPs, database URLs, provider tokens, raw health records or private notes.

## Deployment gates

Before production Admin API deployment:

1. all canonical PostgreSQL migration/schema tests are green;
2. Admin API format/type/unit/security checks are green;
3. PostgreSQL restore drill includes `lifemate_admin_runtime` and proves health-table denial;
4. allowed origins are explicitly configured;
5. Founder bootstrap subject is configured only for the controlled bootstrap window;
6. AAL2 enrollment/challenge flow is available to the intended administrator;
7. the frontend repository is private and `main` is protected with required CI;
8. no production secret appears in Git, build logs or browser-exposed environment variables.

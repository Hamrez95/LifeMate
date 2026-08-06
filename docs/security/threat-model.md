# LifeMate threat model

## Assets

Authentication sessions, account/person graph, phone/email PII, medications and adherence, women-health data/private notes, child/dependent data, consent history, profile media, billing state, audit evidence and export policy.

## Actors

Owner, caregiver/family member, future clinician/coach, malicious authenticated user, unauthenticated attacker, compromised device, SMS/OIDC provider, payment/store provider, internal operator and external analytics partner.

## Trust boundaries

Mobile client -> Supabase Auth -> LifeMate healthcare API -> PostgreSQL/Storage; and OLTP -> controlled extraction -> policy/consent/de-identification -> analytics store/export.

## Primary abuse cases and controls

| Threat | Required control |
|---|---|
| IDOR / cross-person read | central person-scope authorization; unrelated-user tests |
| revoked caregiver still reading | relationship-context grant revocation; fail closed |
| women private-note leak | owner-only query/mapping tests; never audit note content |
| account takeover by identity linking | re-auth both identities; never email-match as proof |
| OTP brute force/replay | short TTL, max attempts, per-phone/IP/device throttling, one-time consumption |
| credential/PII leakage | secret store, structured redacted logs, no health/OTP in SMS/logs |
| direct database access | no client DB credentials; no anon/authenticated privileges on health schemas |
| SQL injection | parameterized queries only; validation; no arbitrary export SQL |
| commercial health-data leakage | export allowlist, source/consent/jurisdiction policy, default disabled |
| Health Connect commercialization | hard policy deny regardless of general secondary-use consent |
| child data secondary use | default deny until legal/policy review explicitly changes it |
| stale JWT after deletion request | account status gate on every healthcare request plus session-revocation workflow |

Security regression covers BOLA/IDOR, consent/grant expiry and revocation, OTP/identity-link takeover, SQL injection attempts, log redaction and restricted-source export denial.

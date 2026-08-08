# Identity and person model

## Concepts

`identity.accounts` represents a principal that can authenticate. `core.persons` represents a human/data subject. They are intentionally independent.

An existing LifeMate account receives a `Self` link to a person with the same UUID during compatibility migration. This preserves every current API/domain identifier while making future child, dependent and professional scenarios possible.

## Identity providers

`identity.external_identities` stores provider identity using `(provider, issuer, provider_subject)` as the unique external key. Email is never used to automatically link Google identities. Google OIDC must use `sub`; account linking requires re-authentication of both sides and must not be based on matching email alone.

Current Supabase Auth identities are represented as provider `supabase_auth` with their immutable auth user UUID as `provider_subject`. A later Google identity can coexist on the same LifeMate account.

## Contact points

Phone/email contact data belongs in `identity.contact_points`, not health-domain tables. Normalized lookup keys use a server-side keyed digest/blind index. Plaintext values must not be indexed merely for convenience. Compatibility phone/email fields remain temporarily in `lifemate.user_profiles` until clients and invitation flows no longer require them.

Iran phone numbers are normalized to E.164 before hashing or sending to the provider.

## Phone OTP abstraction

The runtime-facing contract is provider-independent:

```text
IPhoneOtpProvider
  SendAsync(E164 phone, opaque challenge)
  VerifyAsync(opaque challenge, presented code)
```

The Kavenegar adapter receives its credential only from the runtime secret store. OTP plaintext must never be stored, logged, traced or sent to analytics. Challenges store only a slow/keyed verifier, expiration, attempt count, resend throttle and optional risk hashes. Replay is prevented by one-time consumption.

## Google OIDC

Use Authorization Code + PKCE, `state`, `nonce`, issuer/audience validation and minimal scopes: `openid email profile`. Tokens are not persisted unless a future integration genuinely needs them; if persisted, use envelope encryption and key rotation.

## UUID strategy

The connected PostgreSQL is 17. Native PostgreSQL UUIDv7 is therefore not available. Although modern .NET can generate UUIDv7, the current Edge runtime creates UUIDv4 values. This refactor keeps the PostgreSQL `uuid` type and relies on time-oriented composite indexes for hot event access. UUIDv7 can be adopted only after all writers share a production-safe generator and migration/benchmark evidence exists.

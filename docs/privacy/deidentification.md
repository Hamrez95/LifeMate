# De-identification boundary

External partners never query production OLTP directly.

```text
OLTP
 -> controlled metric/query allowlist
 -> source + purpose + jurisdiction + consent policy
 -> removal/pseudonymization
 -> age/date/location generalization
 -> small-cell and rare-combination suppression
 -> aggregate computation
 -> optional differential privacy for suitable metrics
 -> isolated analytics store/export
 -> audited delivery
```

No export contains LifeMate account/person IDs, contact PII, profile media, OIDC subject, device/IP identifiers, exact address, invitation identifiers, payment/store identifiers or raw audit identity.

The configurable initial minimum cohort size is 20. This is a conservative engineering suppression threshold, not a legal or mathematical guarantee of anonymity. Rare-combination checks may require a larger cohort or complete suppression. Partner access is metric/report allowlisted; arbitrary SQL export is forbidden.

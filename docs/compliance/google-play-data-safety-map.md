# Google Play Data Safety inventory map

This file is the engineering source for the future Play Console declaration. Values must be re-verified immediately before release against the actual app build and third-party SDKs.

| Data category | LifeMate location | Purpose | Sharing default | User deletion |
|---|---|---|---|---|
| account identifiers | `identity.accounts`, Supabase Auth | authentication/security | no partner sharing | deletion workflow |
| phone/email | `identity.contact_points` (legacy profile during migration) | login/contact/invites | no health partner sharing | deletion/retention policy |
| profile | `core.person_profiles` | app personalization | relationship-limited | deletion workflow |
| medications/treatment | health domain by `person_id` | treatment management | scoped caregiver only | health retention/deletion policy |
| adherence | dose events | treatment history/caregiver support | scoped caregiver only | health retention/deletion policy |
| women health | women-health domain | tracking | default private; explicit summary only | high-sensitivity policy |
| profile photo | private Storage | personalization | signed/authorized presentation only | delete object/path |
| billing/subscription | `commerce` | purchase/entitlement | payment/store provider as necessary | financial/retention policy |
| diagnostics | redacted operational telemetry | reliability/security | processor only if configured | bounded retention |
| Health Connect data | provenance-restricted health records | visible user health feature only | commercial export denied | platform/policy-aligned deletion |

Before every release, inspect manifests, Health Connect declarations, analytics/crash SDKs and network calls. The Play Console form must describe actual collection/sharing, not architecture intent.

# Data classification

| Class | Examples | Logging | Access | Retention/export |
|---|---|---|---|---|
| PUBLIC | published help, product catalog labels | allowed | public | product policy |
| INTERNAL | release metadata, non-secret operational IDs | minimal | workforce/service | operational policy |
| PERSONAL | display name, locale | avoid values in routine logs | owner/explicit service | delete/minimize |
| SENSITIVE | phone, email, precise location, identity provider subject | never plaintext in app logs/analytics | identity boundary only | purpose-bound |
| HEALTH | medications, adherence, care events | IDs/action only; no raw payload | owner or scoped grant | health policy |
| HIGHLY_SENSITIVE | menstrual/pregnancy/clinical notes/child health | never raw in logs/audit metadata | explicit narrow scopes/consent | export default deny |

Payment receipts/provider tokens are sensitive commerce data and are isolated from health records. Analytics exports must not include account/person IDs, phone/email/name/photos, OIDC subjects, device identifiers, IPs, precise address, invitation IDs, raw audit identities or billing transaction identifiers.

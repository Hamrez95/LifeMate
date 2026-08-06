# Data provenance

Important health/fitness records preserve origin using a constrained source category:

- `FirstPartyUserInput`
- `CaregiverInput`
- `ClinicianInput`
- `DeviceSensor`
- `HealthConnect`
- `ImportedProvider`
- `PartnerIntegration`
- `SystemGenerated`

Provenance is immutable evidence for policy decisions. Eligibility for secondary use is evaluated from source + current consent + data-subject category + jurisdiction + purpose + export policy. It is never hard-coded solely from a user's general consent.

`HealthConnect` is marked restricted and is hard-blocked from commercial/pharmaceutical export. Child/dependent health data is default denied for secondary commercial use.

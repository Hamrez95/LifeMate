# Google Play health compliance map

Verified against official Google Play documentation on 2026-08-07. This is an engineering compliance checklist, not legal advice.

Official references:

- Health apps declaration: https://support.google.com/googleplay/android-developer/answer/14738291
- Health content and services: https://support.google.com/googleplay/android-developer/answer/16679511
- Health Connect / health-permission data policy: https://support.google.com/googleplay/android-developer/answer/12991134
- Account deletion requirements: https://support.google.com/googleplay/android-developer/answer/13327111
- Health Connect policy update/health records: https://support.google.com/googleplay/android-developer/answer/15931464

## Launch requirements

- Complete the Play Console Health Apps declaration for every distributed track where required, including testing tracks.
- Publish a public, non-geofenced, non-PDF privacy policy and link it in-app.
- Map every declared health/data purpose to the implemented data inventory and actual runtime behavior.
- Request only permissions necessary for visible user features and provide prominent disclosure where required.
- Use encrypted transport and secure at-rest storage appropriate to the data class.
- Do not put health data, private notes, OTPs or contact PII in diagnostics/analytics logs.
- If the app is not a regulated medical device, avoid diagnostic/treatment claims and provide the required health/medical disclaimer and professional-care guidance.
- Provide an in-app account-deletion path and a web deletion-request resource; delete associated data except documented legitimate retention obligations.

## Restricted health sources

Data read through Android health permissions/Health Connect is personal and sensitive. LifeMate marks it `HealthConnect` + restricted and hard-blocks it from commercial/pharmaceutical analytics. A generic user opt-in does not override the platform-purpose restriction.

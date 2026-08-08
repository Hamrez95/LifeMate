# Consent model

Consent is a first-class, versioned domain. Relationship, authorization, entitlement and consent are separate facts.

- `consent_documents`: document/purpose/version/jurisdiction metadata.
- `consent_records`: one subject decision for a versioned purpose/scope, including grant/revoke/expiry status.
- `consent_events`: append-oriented evidence of grant, revoke, expire or supersede actions. History is never erased by revocation.
- `data_use_consents`: explicit secondary-use decisions, independent from care sharing and Terms acceptance.

Secondary analytics/research/commercial consent defaults to opted out. Absence of a positive, current record is denial.

Suggested purposes include `care_sharing`, `product_analytics`, `research`, `commercial_aggregated_analytics`. Data categories and jurisdiction are explicit, not hidden inside general Terms.

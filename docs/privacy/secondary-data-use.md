# Secondary data use

Commercial/pharmaceutical analytics is **DISABLED by default**. This refactor creates only the safety foundation, not a commercial export feature.

Enabling any commercial export requires documented legal, Google Play/policy, consent and jurisdiction review. A controlled extraction path must evaluate provenance, subject category, purpose and current opt-in before de-identification/aggregation.

Hard policy denies:

- Health Connect / Android health-permission sourced records for commercial/pharma export.
- child/dependent health records for commercial use unless a future reviewed policy explicitly permits a narrowly defined use.
- raw user-level health records, identity/PII, billing IDs and unrestricted partner queries.

Every extraction/export attempt is audited, including denied attempts, without copying raw health payloads into audit metadata.

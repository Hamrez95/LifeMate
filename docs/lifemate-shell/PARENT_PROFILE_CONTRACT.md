# LifeMate Parent-App Profile Contract

Status: **approved implementation contract for #1068**

Parent Epic: #1061  
Living Camp: #1058  
Navigation contract: #1066  
Parent app foundation: #1067  
Profile / You UX: #1069  
Profile implementation: #1080

This document defines how the LifeMate parent shell consumes and edits the global Person/Profile state required by `You`, Living Camp presentation, localization and shell preferences. It is a contract boundary, not a schema migration or a second profile store.

## 1. Non-negotiable identity boundary

The parent shell must preserve these distinctions:

- **Account != Person** — authentication/session identity is not the human profile record.
- **Person != relationship target** — a Person may appear through relationship/care flows, but that does not grant access.
- **Relationship != Consent** — Circle presentation cannot infer consent from a relationship row.
- **Enrollment != Entitlement** — product availability and paid access remain separate concerns.
- **Entitlement != Authorization** — paid access never authorizes access to another Person's protected data.

The parent app must reuse the canonical active Person resolved through the reviewed Account → Person bootstrap. It must not create `lifemate`-specific copies of name, DOB, locale, timezone, avatar or preferences.

## 2. Canonical LIVE data observed for #1068

The production `lifemate` Supabase project was read-only verified on 2026-09-11.

### `core.persons`

Relevant existing columns:

| Field | Canonical column | Notes |
| --- | --- | --- |
| Person identity | `core.persons.id` | canonical Person ID; never replace with account ID |
| Birth date | `core.persons.birth_date` | nullable date; source for age-band resolution |
| Region | `core.persons.home_region` | nullable region-level value; **not** a precise location contract |
| Person status | `core.persons.status` | canonical lifecycle state |

### `core.person_profiles`

Relevant existing columns:

| Field | Canonical column | Notes |
| --- | --- | --- |
| Display name | `core.person_profiles.display_name` | global Person presentation name |
| Locale | `core.person_profiles.locale` | current canonical locale storage |
| Time zone | `core.person_profiles.time_zone` | current canonical IANA-style timezone storage |
| Avatar key | `core.person_profiles.avatar_key` | existing generic avatar reference; semantics must remain backward-compatible |
| Profile photo | `core.person_profiles.profile_photo_path` | optional profile media reference |
| Demographic fields | existing profile columns | not Living Camp authorization or progression inputs |

### `core.account_person_links`

This table links Account and Person identities. The parent shell may consume the resolved active Person context through reviewed bootstrap/API boundaries; it must not treat a raw link row as profile truth or authorization for unrelated Persons.

## 3. Parent profile read model

The shell-facing contract is a resolved, privacy-minimized model. Exact transport types may evolve, but semantic fields remain stable.

Illustrative contract:

```text
ParentProfileSnapshot v1
  personId                stable opaque Person ID
  displayName             optional presentation name
  birthDate               optional local-date value
  locale                  supported locale code
  timeZone                IANA timezone ID
  city                    optional coarse user-selected city presentation
  avatar
    family                stable visual family ID
    skinTone              stable palette/tint ID
    lifeStage             resolved presentation stage
  preferences
    reducedMotion         boolean / platform-derived fallback
    ambientAudioEnabled   boolean
  provenance
    version               contract version
    updatedAt             server timestamp where available
    incompleteFields      stable field IDs requiring truthful fallback
```

The shell must not add raw health observations, diagnoses, medication names, pregnancy details, relationship secrets or clinical severity to this profile snapshot.

## 4. Field ownership and derivation matrix

| Shell field | Authority | Rule |
| --- | --- | --- |
| `personId` | canonical Person resolution | immutable shell identity key; never derived from Auth UID |
| `displayName` | `core.person_profiles.display_name` | global presentation only |
| `birthDate` | `core.persons.birth_date` | editable only through reviewed Person/Profile API |
| `locale` | `core.person_profiles.locale` | drives shell localization; unsupported values fall back safely |
| `timeZone` | `core.person_profiles.time_zone` | canonical timezone source for local scheduling/presentation |
| `city` | **not yet observed as a dedicated canonical field** | do not invent storage in Flutter; #1080 must use an approved backend field/adapter before persistence |
| `avatar.family` | **not yet observed as a dedicated canonical field** | stable visual identifier; do not overload biological sex/gender fields |
| `avatar.skinTone` | **not yet observed as a dedicated canonical field** | cosmetic presentation only; never infer ethnicity |
| `avatar.lifeStage` | derived presentation | resolved from DOB + approved age bands, not persisted as age truth |
| `preferences.reducedMotion` | preference/platform adapter | user preference may override or combine with platform accessibility setting; storage contract must be reviewed before persistence |
| `preferences.ambientAudioEnabled` | preference adapter | default remains off; storage contract must be reviewed before persistence |

**Important:** #1068 defines the semantic contract only. It does **not** authorize speculative columns/tables for currently unresolved fields. Any persistence extension must land through an explicit reviewed backend task/migration and then be reflected here.

## 5. Age-band / avatar life-stage contract

Living Camp presentation uses the approved visual life-stage mapping:

| Age at local reference date | Visual stage ID |
| --- | --- |
| 0–5 | `age_2` |
| 6–15 | `age_10` |
| 16–24 | `age_20` |
| 25–39 | `age_30` |
| 40–59 | `age_50` |
| 60+ | `age_70` |

Rules:

1. Age is calculated from canonical `birthDate` using a deterministic local-date algorithm.
2. The stage ID is **presentation state**, not Person identity or medical age classification.
3. A stage boundary does not silently replace the user's visible avatar. The approved Chapter Transition flow owns user confirmation.
4. Missing DOB yields an explicit unresolved/default presentation state; the shell must not guess age from account creation, product usage, gender, photo or other signals.
5. Future age-stage catalogs may add variants without changing the canonical Person model.

## 6. Avatar contract

Avatar state is intentionally separate from demographics and clinical data.

### Stable dimensions

- `familyId` — visual character family identity, versionable and extensible;
- `skinToneId` — cosmetic palette/tint key;
- `lifeStageId` — resolved presentation stage;
- future cosmetic IDs may be added behind versioned manifests.

### Forbidden coupling

The parent shell must not:

- infer `familyId` from sex assigned at birth or gender identity;
- infer `skinToneId` from ethnicity, nationality, photo analysis or location;
- use avatar family/stage as authorization, entitlement or progression truth;
- make Rive artboard names or asset file paths canonical profile values.

Canonical profile values must remain stable identifiers that an asset/manifest adapter resolves into current art. This allows characters, themes, Rive versions and future stage packs to change without rewriting Person data.

## 7. Locale, timezone and city

### Locale

- Supported shell locales begin with Persian (`fa`) and English (`en`).
- Stored locale is canonical preference; route IDs, module IDs and database identifiers remain locale-neutral.
- Unsupported/legacy values must use a deterministic fallback and remain editable.

### Timezone

- Store/transport an IANA timezone ID where the canonical API supports it.
- Timezone is not inferred permanently from device locale.
- Device timezone may be offered as an explicit suggestion during setup/editing.
- Health scheduling continues to use the reviewed shared execution/API contracts; Shell Profile does not create an independent scheduler.

### City

Living Camp day/night may eventually use a coarse saved city/location source for sunrise/sunset. #1068 does not find a dedicated canonical city column in the current core Person/Profile tables.

Therefore:

- do not persist city in local Flutter-only state as authoritative profile truth;
- do not store precise coordinates as a shortcut;
- do not overload `home_region` without an explicit compatibility decision;
- until a reviewed city adapter exists, day/night uses the approved timezone/local fallback behavior from Living Camp contracts.

## 8. Motion and ambient-audio preferences

These are shell presentation preferences, not health state.

### Reduced Motion

Effective motion policy must combine:

1. platform accessibility / reduced-motion signal;
2. optional explicit LifeMate preference when the reviewed persistence adapter exists;
3. feature-level mandatory safety/usability behavior.

If either platform accessibility or explicit user preference requests reduced motion, nonessential Camp motion is disabled. Functional transitions/actions remain available through standard UI and semantics.

### Ambient audio

- default: **off**;
- enabling audio requires explicit user action;
- audio preference must not control alerts, medication reminders or safety-critical notification channels;
- background/lifecycle rules must pause ambient audio independently from notification behavior.

No persistence schema is introduced by #1068 for these preferences.

## 9. Read/write API boundary

Flutter must not query/update `core.persons` or `core.person_profiles` directly.

The parent app consumes a reviewed shared client/API contract. Conceptually:

```text
GET parent-profile
  -> ParentProfileSnapshot v1

PATCH parent-profile
  -> accepts only explicitly editable fields
  -> validates version/authorization
  -> returns canonical updated snapshot
```

The exact endpoint names are implementation details owned by the API/client task that exposes the contract. The important boundary is:

- Auth/session resolves Account;
- reviewed server logic resolves the active Person;
- server/API enforces authorization and validation;
- Flutter receives presentation-safe profile state;
- Flutter never becomes authoritative for Person identity or trusted backend state.

### Patch semantics

A future write request must be partial and explicit. Absence means "unchanged"; clearing a nullable value must be distinct from omission.

Server-side validation must cover at minimum:

- valid local-date DOB and reasonable domain bounds;
- supported locale format;
- valid IANA timezone ID;
- allowed stable avatar/preference IDs from versioned catalogs;
- optimistic concurrency/version semantics if concurrent edits are supported.

## 10. Loading, incomplete, offline and error states

Profile consumers must handle state truthfully.

### Loading

- show structural placeholders/skeletons;
- do not display fabricated name, age, avatar stage or city.

### Incomplete profile

- valid Person with missing optional fields remains usable;
- You screen may prompt completion without blocking unrelated shell access;
- Living Camp uses deterministic neutral/default visuals where allowed;
- missing DOB never becomes a guessed age stage.

### Offline

- previously authorized, non-sensitive profile presentation may be shown from safe cache;
- cached data is labeled/styled as ordinary presentation, not proof of current authorization for another Person;
- edits queue only through the shared reviewed offline/outbox mechanism if/when supported; #1068 does not create another queue.

### Error / stale

- preserve last safe presentation where policy permits;
- expose retry through standard UI/semantics;
- do not reset canonical profile fields locally because a refresh failed.

### Revoked / invalid active Person

If Account→Person resolution is no longer valid, fail closed into the existing bootstrap/recovery flow. Do not continue with a stale Person merely because the shell has a cached profile.

## 11. RTL/LTR and accessibility contract

Profile semantics must be independent from visual direction.

- Persian uses RTL layout; English uses LTR.
- Stable field IDs and transport keys remain locale-neutral.
- dates are localized for display but transported as canonical date values;
- timezone IDs are not translated internally;
- avatar controls require text/semantic names, selected state and non-color-only distinction;
- skin-tone choices require neutral presentation labels and must not claim race/ethnicity;
- Reduced Motion must be reachable without entering the animated Living Camp scene;
- ambient audio control must expose on/off state to assistive technology.

## 12. Privacy and analytics

Allowed analytics are event/category level, for example:

- profile screen opened;
- profile field edit flow opened;
- preference toggled by stable preference ID;
- avatar customization completed using non-sensitive catalog IDs.

Do not log:

- DOB values;
- display name;
- precise location;
- profile photo path;
- gender/sex fields;
- Person IDs in human-readable analytics labels;
- health data through profile events.

Use opaque correlation identifiers only where the reviewed telemetry contract explicitly permits them.

## 13. Extension model

Future profile dimensions must be additive and versioned.

A new field is acceptable only when:

1. its owning domain is explicit;
2. canonical authority is explicit;
3. read/write authorization is explicit;
4. fallback behavior exists for old clients;
5. it is not encoded into route names, Rive state-machine names or asset paths;
6. standalone products remain compatible during convergence.

Examples of future additions that must remain decoupled:

- new avatar families;
- new life-stage visuals;
- clothing/cosmetic choices;
- themes;
- additional accessibility preferences;
- companion presentation preferences;
- progression presentation IDs.

Progression balances, entitlement state, consent and scene state are **not profile fields**.

## 14. Implementation ownership after #1068

### #1069 — Profile / You UX

Owns page composition, edit flows, field grouping, validation presentation, empty/loading/error states and visual/accessibility behavior using this contract.

### #1080 — Profile implementation

Owns integration with the reviewed API/client adapters. It must not add direct Supabase queries from Flutter.

If #1080 discovers missing canonical persistence for `city`, avatar family/skin tone or shell preferences, it must first use or introduce an explicitly reviewed backend contract. It must not create local-only canonical truth.

### Living Camp consumers

Living Camp may consume only presentation-safe resolved values such as avatar IDs, life-stage presentation and effective motion/audio preferences. It remains unable to infer clinical meaning from raw health data.

## 15. Acceptance checklist for downstream PRs

A PR consuming this contract is conformant when:

- [ ] active Person comes from reviewed Account→Person resolution;
- [ ] no duplicate parent-app profile store is created;
- [ ] no direct sensitive Supabase table access exists in Flutter;
- [ ] DOB is canonical Person data and missing DOB remains unresolved rather than guessed;
- [ ] locale/timezone are locale-neutral transport values with safe fallbacks;
- [ ] avatar family/skin tone are cosmetic stable IDs, not demographic inference;
- [ ] unresolved storage fields do not silently become Flutter authority;
- [ ] Reduced Motion works independently from Camp visuals;
- [ ] ambient audio defaults off and is separate from notification behavior;
- [ ] RTL/LTR and screen-reader semantics are covered;
- [ ] loading/incomplete/offline/error/revoked states are explicit;
- [ ] no Progression, entitlement, consent or scene state is collapsed into Profile;
- [ ] standalone product behavior remains intact.

## 16. Verification evidence for #1068

This contract was reconciled against:

- `docs/lifemate-shell/MASTER_PLAN.md`;
- #1061 / #1068 scope;
- merged navigation contract #1066;
- merged parent app foundation #1067;
- production `core.persons`, `core.person_profiles`, and `core.account_person_links` column metadata on 2026-09-11.

No database mutation, API deployment or Flutter runtime change is required by #1068 itself. The key verified result is the separation between fields that already have canonical storage and fields whose persistence remains intentionally unresolved until a reviewed implementation task supplies it.

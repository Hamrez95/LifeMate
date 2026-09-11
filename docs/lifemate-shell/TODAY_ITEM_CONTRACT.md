# LifeMate Today — Shared Item, Ranking & Alert-Severity Contract

Status: **versioned implementation contract for #1088**

Parent Epic: #1062  
UX contract: #1087 / `TODAY_UX_CONTRACT.md`  
Navigation contract: #1066 / `NAVIGATION_ARCHITECTURE.md`  
Implementation consumers: #1089 Today Peek Sheet / Full Day, #1090 Notification Center

This document defines the normalized module-to-shell contract for Today items and alert severity. It is intentionally a **presentation/read-model boundary**, not a new health domain, notification database, scheduler, entitlement system, or clinical rules engine.

GitHub/API audit at definition time found existing source domains such as canonical Person-authorized care events, treatment/dose occurrences, pregnancy/calendar integrations and shared offline projections. Supabase LIVE had no independent `Today`, `alert`, or `notification` table/routine. Therefore this contract aggregates reviewed source outputs instead of creating another source of truth.

## 1. Non-negotiable boundaries

- **Account != Person**
- **Relationship != Consent**
- **Enrollment != Entitlement**
- **Entitlement != Authorization**
- Today does not own canonical medication, appointment, pregnancy, care, activity or other module records.
- Today does not calculate clinical meaning from raw observations or measurements.
- Flutter does not mint severity, trusted health state, entitlement or authorization.
- A cached relationship, entitlement or companion presentation is never proof of current authorization.
- Navigation intent is not authorization.

The shell receives already-normalized presentation state from a reviewed source/module adapter or future authorized Today aggregation endpoint.

## 2. Contract version

Canonical contract identifier:

```text
lifemate.today.v1
```

Every serialized snapshot must declare:

```text
schemaVersion = "lifemate.today.v1"
```

Rules:

- additive optional fields may be introduced within v1 when old consumers can safely ignore them;
- required-field or semantic changes require a new major contract version;
- an unknown major version must fail to a truthful degraded/error state;
- consumers must not guess at unknown enum meanings;
- a new source module can join the contract without changing existing source modules.

## 3. Normalized alert severity

The shared v1 severity vocabulary is exactly:

```text
normal
needs_attention
urgent
```

### `normal`

Routine Today information/action with no reviewed need for enhanced attention presentation.

### `needs_attention`

The source/domain adapter has explicitly normalized the item as needing bounded additional attention. Today may use text, iconography and calm visual emphasis; future Living Camp presentation may use a bounded zone pulse.

### `urgent`

The source/domain adapter has explicitly normalized the item as urgent/safety-sensitive and supplied an appropriate standard product action/presentation contract.

`urgent` does **not** itself mean emergency services, a diagnosis, or a specific clinical instruction. The generic shell must never invent those meanings.

### Authority rule

Only a reviewed source/module/domain adapter may assign severity from its authoritative semantics.

The shell must **not** infer severity from:

- blood pressure, glucose, weight, heart rate, BMI or other raw measurements;
- medication names/doses;
- diagnosis strings;
- pregnancy data;
- arbitrary text keywords;
- local visual state;
- entitlement or progression state.

If a source cannot safely normalize severity, use `normal` only when that is explicitly its reviewed default. Unknown/invalid severity values are contract errors; the shell must not silently downgrade them.

## 4. Ranking contract

Approved product order is:

1. safety / overdue;
2. due soon;
3. personal priority.

To keep this deterministic and prevent UI widgets from inventing clinical/task rules, every displayable item carries a normalized ranking tier assigned by its reviewed source/aggregation layer:

```text
safety_or_overdue
due_soon
personal_priority
later
```

`later` is the safe catch-all for valid Today items that belong to the day but are not in the first three priority tiers.

### Shell sort order

Consumers sort only by normalized fields:

1. `rankTier` in the canonical order above;
2. `sortAt` ascending when both items supply it;
3. `stableSortKey` ascending as deterministic final tie-breaker.

The shell never promotes/demotes an item by reading raw domain values.

### Source responsibility

A source/aggregation adapter owns decisions such as:

- whether a domain item is overdue;
- whether a time window counts as due soon;
- whether an item qualifies as personal priority;
- whether a safety-sensitive domain event belongs in `safety_or_overdue`.

Generic Today code owns only ordering of the supplied normalized values.

## 5. Snapshot contract

Normative conceptual shape:

```text
TodaySnapshotV1
  schemaVersion: "lifemate.today.v1"
  generatedAt: instant
  freshness: TodayFreshness
  completeness: TodayCompleteness
  items: List<TodayItemV1>
  unavailableSources: List<TodaySourceStatusV1>
```

### `generatedAt`

Timestamp at which the resolved snapshot was produced. It is presentation/read-model provenance, not a health event timestamp.

### `freshness`

```text
live
cached
```

A cached snapshot must never be presented as current without an explicit cached/offline treatment.

### `completeness`

```text
complete
partial
```

`partial` is valid only when the producer can identify that one or more source domains failed/are unavailable while the remaining items are safe to show.

If trustworthy partial provenance is unavailable, return an overall error rather than pretending a partial snapshot is complete.

### `unavailableSources`

Presentation-safe source status only. It must not leak protected record counts, diagnoses, consent reasons, or backend error details.

Example fields:

```text
sourceModuleId
reason: unavailable | refresh_failed | authorization_changed
```

## 6. Today item contract

Normative conceptual shape:

```text
TodayItemV1
  itemId: opaque stable item identity
  sourceModuleId: stable module registry ID
  owner: TodayOwnerPresentationV1
  display: TodayDisplayContentV1
  severity: normal | needs_attention | urgent
  rankTier: safety_or_overdue | due_soon | personal_priority | later
  sortAt: optional instant
  stableSortKey: stable non-sensitive string
  due: optional TodayDuePresentationV1
  state: actionable | completed | unavailable
  action: optional TodayActionIntentV1
  sourceUpdatedAt: optional instant
```

### `itemId`

Opaque identity within the Today read model. It may map to a canonical source record internally, but UI/analytics must not parse business meaning from it.

Do not encode PHI, medication names, diagnoses or Person display names in the ID.

### `sourceModuleId`

Stable locale-neutral module registry identity such as the registry IDs owned by #1081.

It is not:

- a localized app name;
- an entitlement value;
- a Camp `zoneId`;
- a database table name;
- authorization proof.

### `owner`

Presentation-safe owner context supplied after authorization has been resolved.

### `display`

Human-readable presentation payload. It may contain sensitive text appropriate for the currently authorized in-app view, so it must not be copied blindly into analytics, URLs, logs or notification metadata.

### `severity` / `rankTier`

Already normalized by the producer. The UI renders/sorts them; it does not derive them.

### `sortAt`

Optional normalized timestamp used for deterministic ordering. It can represent the producer's chosen relevant execution/due time without forcing the shell to understand source-domain scheduling semantics.

### `stableSortKey`

Required deterministic tie-breaker that contains no PHI. Recommended shape is an opaque generated ID or stable source namespace + opaque ID.

### `state`

```text
actionable
completed
unavailable
```

`state` is Today presentation state only and must not replace canonical module status.

## 7. Owner presentation contract

Conceptual shape:

```text
TodayOwnerPresentationV1
  kind: current_person | companion
  presentationId: opaque shell-local identity
  displayName: localized/authorized display string
  avatarRef: optional safe presentation reference
```

Rules:

- `current_person` means the currently resolved Person, not merely the authenticated Account;
- `companion` may be emitted only after relationship + consent + authorization checks relevant to the source are satisfied;
- `presentationId` is for list identity and UI reconciliation, not authorization;
- revocation removes protected items on refresh/revalidation;
- a cached companion item must never survive solely because `presentationId` is still known;
- analytics must not log `displayName` or companion identity.

The shell may localize a generic `You` label for `current_person`; companion display naming remains authorization-aware.

## 8. Display content contract

Conceptual shape:

```text
TodayDisplayContentV1
  title: string
  subtitle: optional string
  timeLabel: optional string
  ownerLabelOverride: optional string
  sourceLabel: optional string
  accessibilitySummary: optional string
```

Guidance:

- producer supplies clinically/domain-correct human-readable text;
- the shell may apply normal localization wrappers but does not rewrite medical meaning;
- absence of `subtitle` or `timeLabel` is valid;
- `accessibilitySummary` supplements structured semantics; it must not be the only source of critical state;
- arbitrary rich HTML/Markdown is not accepted in v1;
- raw backend error messages never become display content.

## 9. Due presentation

Conceptual shape:

```text
TodayDuePresentationV1
  instant: optional instant
  localDate: optional YYYY-MM-DD
  localTime: optional HH:mm
  timeZone: optional IANA zone
  label: optional safe localized display label
```

The producer chooses the applicable representation.

The shell may format supplied timestamps for locale/timezone, but must not infer clinical grace windows, missed-dose rules or urgency from them.

## 10. Action intent contract

Conceptual shape:

```text
TodayActionIntentV1
  kind: module_route | shell_route | refresh_only
  moduleId: optional stable module ID
  routeId: stable locale-neutral action/route identity
  opaqueTargetId: optional opaque identifier
  requiresOnlineRevalidation: bool
```

Rules:

- no diagnosis, medication name, health measurement, pregnancy status or Person display name in route IDs/opaque target IDs;
- `moduleId` resolves through the canonical module registry/route host;
- opening an action revalidates current enrollment/entitlement/authorization as applicable;
- a stale cached intent never proves access;
- unsupported module/route/version produces truthful unavailable state;
- `refresh_only` allows an item to request refresh/revalidation without inventing a destination.

The shell must not hard-code product-internal page graphs into Today.

## 11. Source adapter boundary

A source adapter converts an authoritative product/domain output into `TodayItemV1`.

Examples of existing source families observed in the repository include:

- treatment plans and dose occurrences;
- Person-authorized care events;
- pregnancy/calendar-linked care events;
- future reviewed module outputs.

The adapter owns domain interpretation. Today owns aggregation/presentation only.

### Required adapter responsibilities

Before emitting an item, the adapter must:

1. operate on authorized source data;
2. choose a presentation-safe owner;
3. normalize severity according to reviewed source rules;
4. assign normalized rank tier;
5. provide deterministic sort fields;
6. provide safe display content;
7. provide an authorization-safe action intent;
8. identify whether the item may be cached/offline and under which policy.

### Forbidden generic adapter

Do not build a generic reflection/keyword adapter that scans arbitrary source JSON and guesses severity, title, owner or navigation.

## 12. Aggregation boundary

The canonical Today aggregation implementation may eventually live behind the reviewed LifeMate API/shared client boundary. #1088 defines the contract but does **not** require creating a speculative database table or endpoint before source adapters are designed.

A production aggregator must:

- request only authorized Person/source contexts;
- merge normalized items from registered source adapters;
- deduplicate only using explicit source identity rules;
- apply the deterministic shared sort contract;
- produce top-three by taking the first three actionable/displayable items from the sorted snapshot;
- expose complete/partial/freshness provenance;
- never join raw sensitive tables directly from Flutter.

The current parent app may use injected contract fixtures during #1089 UI tests, but fixtures are test evidence only and never production canonical truth.

## 13. Top-three rule

Peek Sheet top-three selection is mechanical:

1. start from the already-authorized, normalized and sorted Today snapshot;
2. include displayable items in contract order;
3. take at most the first three;
4. never add fabricated filler rows;
5. if fewer than three exist, show fewer than three;
6. Full Day receives the complete displayable sorted set.

Widgets must not perform a second ranking pass.

## 14. Offline and cache semantics

#828 remains authoritative for shared owner-health offline execution.

### Current Person / owner-local items

Owner-local items may be presented from safe shared offline projections when the source adapter explicitly supports that path.

Today must not create a separate medication/care-event database or scheduler.

### Companion/shared items

Cached shared items are **not proof** that relationship, consent or authorization remains valid.

A source adapter must either:

- revalidate authorization before returning the item; or
- omit/protect shared items while offline when safe revalidation is unavailable.

### Cached snapshot label

`freshness = cached` requires explicit cached/offline UX from #1087/#1089.

## 15. Error model

Contract-level failures are separated from source-level partial failures.

### Whole snapshot errors

Examples:

- unsupported schema version;
- invalid required enum/value;
- authorization context unavailable;
- producer cannot establish trustworthy completeness/freshness.

Consumer shows the approved error/offline/degraded state and does not fabricate data.

### Source-level partial failure

Allowed only when remaining items are independently safe and `completeness = partial` plus `unavailableSources` accurately describes the missing source at a presentation-safe level.

Do not expose stack traces, SQL errors or raw API payloads.

## 16. Unknown values and forward compatibility

### Unknown schema major

Reject/degrade safely.

### Unknown severity

Do **not** silently convert to `normal`. Reject that item/snapshot according to producer validation policy and surface degraded provenance.

### Unknown rank tier

Do **not** guess where it belongs. Treat as contract-invalid.

### Unknown module

Do not invent a route. Item may be shown only if display remains safe and action can truthfully be unavailable; otherwise omit it with partial/degraded provenance.

### Unknown optional field

Ignore when v1 compatibility rules allow it.

## 17. Notification Center reuse

#1090 should reuse this severity vocabulary and safe action-intent boundary where its source semantics overlap.

Notification delivery records and Today items are not automatically the same domain object.

Rules:

- Today does not become a notification inbox;
- Notification Center does not become the canonical Today scheduler;
- a notification may resolve to a Today/module action using the same safe route intent;
- severity mapping must remain consistent across surfaces;
- external/push payloads must remain minimal and must not contain display PHI merely because in-app `TodayDisplayContentV1` can.

## 18. RTL/LTR and accessibility contract

Data contract fields stay locale-neutral except explicitly presentation-ready strings.

Consumer requirements:

- owner, title, due/time and severity are exposed as one understandable semantic item;
- severity has text/semantic meaning independent of color/motion;
- source/module labels are localized presentation and never source identity;
- time/date formatting follows locale/directionality without changing canonical instants;
- mixed Persian/Latin module names remain readable;
- large text may reflow rows; the data contract imposes no fixed-height assumptions;
- action availability remains reachable under Reduced Motion.

## 19. Privacy and analytics

The following must not be copied into generic analytics dimensions:

- `display.title` / `display.subtitle`;
- Person/companion display name;
- medication/diagnosis/appointment text;
- raw source payloads;
- `opaqueTargetId` unless an analytics contract explicitly proves it non-sensitive.

Safe analytics may use reviewed low-cardinality values such as:

- source module ID;
- severity enum;
- rank tier;
- action kind;
- freshness/completeness.

Even safe-looking IDs remain subject to the repository's analytics/privacy policy.

## 20. Example — non-clinical synthetic fixture

This example is illustrative test data only:

```json
{
  "schemaVersion": "lifemate.today.v1",
  "generatedAt": "2026-09-11T07:00:00Z",
  "freshness": "live",
  "completeness": "complete",
  "items": [
    {
      "itemId": "item_a1",
      "sourceModuleId": "wellmate",
      "owner": {
        "kind": "current_person",
        "presentationId": "owner_current",
        "displayName": "You"
      },
      "display": {
        "title": "Scheduled task",
        "timeLabel": "10:30"
      },
      "severity": "normal",
      "rankTier": "due_soon",
      "sortAt": "2026-09-11T07:00:00Z",
      "stableSortKey": "wellmate:item_a1",
      "state": "actionable",
      "action": {
        "kind": "module_route",
        "moduleId": "wellmate",
        "routeId": "scheduled_task",
        "opaqueTargetId": "target_a1",
        "requiresOnlineRevalidation": false
      }
    }
  ],
  "unavailableSources": []
}
```

Do not use this fixture as production content or clinical logic.

## 21. Conformance evidence required from #1089 / future adapters

At minimum, automated tests should demonstrate:

1. canonical rank-tier ordering;
2. `sortAt` + stable key deterministic tie-breaking;
3. top-three takes exactly the first three normalized items and never fabricates rows;
4. fewer-than-three behavior;
5. unknown severity is not silently downgraded;
6. unsupported schema version fails safely;
7. partial snapshot exposes degraded provenance;
8. cached snapshot is distinguishable from live;
9. companion/shared item disappears/fails closed when authorization cannot be revalidated;
10. route action goes through module/shell host rather than parsing display text;
11. no raw measurement is required by the generic Today contract;
12. RTL/LTR semantics use localized display strings without changing stable IDs;
13. urgent/needs-attention remains explicit under Reduced Motion and without color;
14. malformed source content cannot inject a route or analytics identity through title/subtitle text.

Source-specific adapters need additional domain tests proving their severity/rank mapping is correct for that domain.

## 22. Security review checklist

Before a production Today aggregator/adapter is enabled:

- source read is authorized at Account/Person boundary;
- companion Relationship and Consent are resolved separately;
- entitlement is not treated as authorization;
- no service-role secret is exposed to Flutter;
- Flutter does not directly query sensitive source tables;
- shared source cache cannot bypass revoked authorization;
- severity mapping is reviewed by the owning product/domain, not inferred generically;
- action intent is revalidated at destination;
- logs/analytics do not capture display PHI;
- partial/offline provenance is truthful.

## 23. Definition of Done for #1088

#1088 is complete when:

- `lifemate.today.v1` is the explicit versioned shared contract;
- `normal`, `needs_attention`, `urgent` semantics and authority are unambiguous;
- normalized rank tiers and deterministic sorting are defined;
- `TodaySnapshotV1`, `TodayItemV1`, owner, display, due and action-intent boundaries are defined;
- source adapters remain owners of domain interpretation;
- top-three selection is mechanical and does not re-rank inside Flutter widgets;
- live/cached and complete/partial provenance are explicit;
- unknown/invalid values fail safely instead of under-stating severity;
- companion/shared offline behavior fails closed when authorization cannot be revalidated;
- #1090 can reuse severity/action semantics without conflating Today and notification storage;
- conformance/security test requirements are defined;
- no speculative Supabase Today/notification schema or direct sensitive Flutter query is introduced.

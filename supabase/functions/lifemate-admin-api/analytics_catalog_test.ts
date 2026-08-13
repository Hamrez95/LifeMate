import { assertEquals, assert } from "jsr:@std/assert";

import {
  EVENT_DEFINITIONS,
  EVENT_TAXONOMY_VERSION,
  KPI_DEFINITIONS,
  KPI_DICTIONARY_VERSION,
} from "./analytics_catalog.ts";

const REQUIRED_EVENTS = [
  "account_created",
  "profile_completed",
  "app_opened",
  "treatment_created",
  "care_invitation_created",
  "care_relationship_activated",
  "trial_started",
  "subscription_started",
  "subscription_renewed",
  "subscription_expired",
  "promotion_redeemed",
  "support_ticket_created",
  "social_post_published",
  "incident_created",
].sort();

Deno.test("analytics taxonomy contains the exact required canonical events", () => {
  assertEquals(
    EVENT_DEFINITIONS.map((event) => event.name).sort(),
    REQUIRED_EVENTS,
  );
  assertEquals(EVENT_TAXONOMY_VERSION, 1);
});

Deno.test("analytics taxonomy is aggregate-safe and versioned", () => {
  for (const event of EVENT_DEFINITIONS) {
    assert(event.version > 0);
    assertEquals(event.payloadPolicy, "aggregate-safe");
    assert(event.source.length > 0);
    assert(event.description.length > 0);
  }
});

Deno.test("every KPI definition has the complete dictionary contract", () => {
  assertEquals(KPI_DICTIONARY_VERSION, 1);
  assert(KPI_DEFINITIONS.length > 0);

  for (const kpi of KPI_DEFINITIONS) {
    assert(kpi.name.length > 0);
    assert(kpi.displayNameFa.length > 0);
    assert(kpi.formula.length > 0);
    assert(kpi.numerator.length > 0);
    assert(kpi.timeWindow.length > 0);
    assertEquals(kpi.timezone, "Asia/Tehran");
    assert(kpi.source.length > 0);
    assert(kpi.freshness.length > 0);
    assert(kpi.definitionVersion > 0);
  }
});

Deno.test("KPI sources reference only canonical events", () => {
  const eventNames = new Set(EVENT_DEFINITIONS.map((event) => event.name));
  for (const kpi of KPI_DEFINITIONS) {
    for (const source of kpi.source) {
      assert(eventNames.has(source), `${kpi.name} references non-canonical event ${source}`);
    }
  }
});

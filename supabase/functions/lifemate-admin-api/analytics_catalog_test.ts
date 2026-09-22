import { assert, assertEquals } from "jsr:@std/assert";

import {
  ANALYTICS_EVENTS,
  EVENT_TAXONOMY_VERSION,
  getAnalyticsCatalog,
  KPI_DEFINITIONS,
  KPI_DICTIONARY_VERSION,
} from "./analytics_catalog.ts";

const requiredEvents = [
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
];

Deno.test("analytics taxonomy exposes every canonical v1 event once", () => {
  assertEquals(EVENT_TAXONOMY_VERSION, 1);
  const names = ANALYTICS_EVENTS.map((event) => event.name);
  assertEquals(new Set(names).size, names.length);
  for (const event of requiredEvents) {
    assert(names.includes(event), `missing canonical event: ${event}`);
  }
});

Deno.test("every KPI has a versioned auditable definition", () => {
  assertEquals(KPI_DICTIONARY_VERSION, 2);
  assert(KPI_DEFINITIONS.length > 0);

  for (const definition of KPI_DEFINITIONS) {
    assert(definition.name.length > 0);
    assert(definition.displayNameFa.length > 0);
    assert(definition.definitionVersion >= 1);
    assert(definition.formula.length > 0);
    assert(definition.numerator.length > 0);
    assert(definition.timeWindow.length > 0);
    assertEquals(definition.timezone, "Asia/Tehran");
    assert(definition.eventSources.length > 0);
    assert(definition.freshnessRule.length > 0);
    assert(
      definition.availability === "available" ||
        definition.availability === "partial" ||
        definition.availability === "unavailable",
    );
  }
});

Deno.test("KPI sources reference only canonical analytics events", () => {
  const events = new Set(ANALYTICS_EVENTS.map((event) => event.name));
  for (const definition of KPI_DEFINITIONS) {
    for (const source of definition.eventSources) {
      assert(
        events.has(source),
        `${definition.name} references unknown event ${source}`,
      );
    }
  }
});

Deno.test("planned instrumentation stays unavailable instead of becoming fake zero", () => {
  const eventState = new Map(
    ANALYTICS_EVENTS.map((event) => [event.name, event.instrumentationState]),
  );

  for (const definition of KPI_DEFINITIONS) {
    const hasPlannedSource = definition.eventSources.some(
      (source) => eventState.get(source) === "planned",
    );
    if (hasPlannedSource) {
      assertEquals(definition.availability, "unavailable");
    }
  }
});

Deno.test("catalog returns versions and definitions without metric values", () => {
  const catalog = getAnalyticsCatalog();
  assertEquals(catalog.eventTaxonomyVersion, 1);
  assertEquals(catalog.kpiDictionaryVersion, 2);
  assertEquals(catalog.events.length, ANALYTICS_EVENTS.length);
  assertEquals(catalog.kpis.length, KPI_DEFINITIONS.length);
  assert(!("values" in catalog));
  assert(!Number.isNaN(Date.parse(catalog.generatedAtUtc)));
});

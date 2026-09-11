import { assertEquals, assertThrows } from "jsr:@std/assert@1.0.14";
import { normalizePregnancyCalendarClassification } from "./pregnancy_calendar.ts";
import {
  paginatePregnancyRecords,
  type PregnancyRecordItem,
} from "./pregnancy_records.ts";
import {
  requireCocoonPregnancyActivationEntitlement,
  requiresCocoonPregnancyActivationEntitlement,
} from "./cocoon_routes.ts";
import { createPregnancyTreatmentRouteHandler } from "./pregnancy_treatments.ts";
import { ApiError } from "./validation.ts";

Deno.test(
  "Cocoon entitlement is rechecked only for pregnancy activation mutations",
  () => {
    assertEquals(
      requiresCocoonPregnancyActivationEntitlement(
        "POST",
        "/api/v1/cocoon/pregnancy/episodes",
      ),
      true,
    );
    assertEquals(
      requiresCocoonPregnancyActivationEntitlement(
        "POST",
        "/api/v1/cocoon/pregnancy/episodes/11111111-1111-4111-8111-111111111111/activate",
      ),
      true,
    );
    assertEquals(
      requiresCocoonPregnancyActivationEntitlement(
        "POST",
        "/api/v1/cocoon/pregnancy/episodes/11111111-1111-4111-8111-111111111111/end",
      ),
      false,
    );
    assertEquals(
      requiresCocoonPregnancyActivationEntitlement(
        "GET",
        "/api/v1/cocoon/pregnancy/episodes",
      ),
      false,
    );
  },
);

Deno.test(
  "Cocoon pregnancy activation allows only an entitled commerce snapshot",
  () => {
    requireCocoonPregnancyActivationEntitlement({
      state: "entitled",
      offerAvailable: false,
      conversionEligible: false,
    });

    const denied = assertThrows(
      () =>
        requireCocoonPregnancyActivationEntitlement({
          state: "offer_available",
          offerAvailable: true,
          conversionEligible: false,
        }),
      ApiError,
    );
    assertEquals(denied.status, 403);
    assertEquals(denied.code, "cocoon_entitlement_required");

    const unavailable = assertThrows(
      () =>
        requireCocoonPregnancyActivationEntitlement({
          state: "error",
          offerAvailable: false,
          conversionEligible: false,
        }),
      ApiError,
    );
    assertEquals(unavailable.status, 503);
    assertEquals(unavailable.code, "cocoon_commerce_unavailable");
  },
);

Deno.test("Cocoon pregnancy calendar accepts only bounded classifications", () => {
  assertEquals(
    normalizePregnancyCalendarClassification(" ULTRASOUND "),
    "ultrasound",
  );
  assertEquals(
    normalizePregnancyCalendarClassification("prenatal"),
    "prenatal",
  );
  const error = assertThrows(
    () => normalizePregnancyCalendarClassification("educational_milestone"),
    ApiError,
  );
  assertEquals(error.status, 400);
  assertEquals(error.code, "pregnancy_calendar_classification_invalid");
});

Deno.test("Cocoon pregnancy treatment context reuses canonical treatment truth", async () => {
  const authorizationCalls: Array<Record<string, string>> = [];
  const handler = createPregnancyTreatmentRouteHandler("unused", {
    resolveIdentity: async () => ({
      accountId: "11111111-1111-4111-8111-111111111111",
      personId: "22222222-2222-4222-8222-222222222222",
    }),
    currentEpisode: async () => ({
      id: "33333333-3333-4333-8333-333333333333",
      status: "active",
    }),
    requireMedicationRead: async (args) => {
      authorizationCalls.push(args);
    },
    listTreatmentPlans: async () => [
      {
        id: "44444444-4444-4444-8444-444444444444",
        status: "active",
        medication: { name: "Canonical medicine" },
      },
      {
        id: "55555555-5555-4555-8555-555555555555",
        status: "archived",
        medication: { name: "Old medicine" },
      },
    ],
    listDoseOccurrences: async () => [
      {
        id: "66666666-6666-4666-8666-666666666666",
        treatmentPlanId: "44444444-4444-4444-8444-444444444444",
        status: "scheduled",
      },
      {
        id: "77777777-7777-4777-8777-777777777777",
        treatmentPlanId: "55555555-5555-4555-8555-555555555555",
        status: "scheduled",
      },
    ],
  });

  const response = await handler({
    request: new Request(
      "https://example.test/api/v1/cocoon/pregnancy/treatments?fromDate=2026-09-11&toDate=2026-09-18",
    ),
    path: "/api/v1/cocoon/pregnancy/treatments",
    appUserId: "88888888-8888-4888-8888-888888888888",
  });
  const body = await response!.json();

  assertEquals(response!.status, 200);
  assertEquals(body.contractVersion, 1);
  assertEquals(body.episodeId, "33333333-3333-4333-8333-333333333333");
  assertEquals(body.mutationAuthority, "canonical_treatment_api");
  assertEquals(body.treatmentPlans.length, 1);
  assertEquals(
    body.treatmentPlans[0].id,
    "44444444-4444-4444-8444-444444444444",
  );
  assertEquals(body.doseOccurrences.length, 1);
  assertEquals(
    body.doseOccurrences[0].treatmentPlanId,
    "44444444-4444-4444-8444-444444444444",
  );
  assertEquals(authorizationCalls, [
    {
      callerAccountId: "11111111-1111-4111-8111-111111111111",
      subjectPersonId: "22222222-2222-4222-8222-222222222222",
      episodeId: "33333333-3333-4333-8333-333333333333",
    },
  ]);
});

Deno.test("Cocoon pregnancy records cursor remains stable when newer items arrive", () => {
  const record = (
    id: string,
    occurredAtUtc: string,
  ): PregnancyRecordItem => ({
    id,
    sourceKind: "test",
    sourceId: id,
    category: "check_ins",
    occurredAtUtc,
    localDate: occurredAtUtc.slice(0, 10),
    type: "test",
    summary: {},
  });
  const initial = [
    record("a", "2026-09-12T10:00:00.000Z"),
    record("b", "2026-09-11T10:00:00.000Z"),
    record("c", "2026-09-10T10:00:00.000Z"),
  ];
  const first = paginatePregnancyRecords(initial, 2, null);
  assertEquals(first.items.map((value) => value.id), ["a", "b"]);
  const cursor = first.nextCursor;
  assertEquals(cursor == null, false);

  const newer = record("new", "2026-09-13T10:00:00.000Z");
  const decoded = JSON.parse(atob(cursor!));
  const second = paginatePregnancyRecords([...initial, newer], 2, decoded);
  assertEquals(second.items.map((value) => value.id), ["c"]);
  assertEquals(second.nextCursor, null);
});

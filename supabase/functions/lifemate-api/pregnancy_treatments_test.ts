import { assertEquals } from "jsr:@std/assert@1.0.14";
import { createPregnancyTreatmentRouteHandler } from "./pregnancy_treatments.ts";

Deno.test("pregnancy treatment context reuses canonical plans and occurrences", async () => {
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

Deno.test("pregnancy treatment adapter ignores unrelated routes", async () => {
  const handler = createPregnancyTreatmentRouteHandler("unused", {
    resolveIdentity: async () => {
      throw new Error("must not resolve identity");
    },
    currentEpisode: async () => null,
    requireMedicationRead: async () => {},
    listTreatmentPlans: async () => [],
    listDoseOccurrences: async () => [],
  });

  const response = await handler({
    request: new Request("https://example.test/api/v1/cocoon/pregnancy/calendar"),
    path: "/api/v1/cocoon/pregnancy/calendar",
    appUserId: "88888888-8888-4888-8888-888888888888",
  });
  assertEquals(response, null);
});

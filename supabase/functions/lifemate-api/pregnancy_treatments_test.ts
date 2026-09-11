import {
  assertEquals,
  assertRejects,
} from "jsr:@std/assert@1.0.14";
import { createPregnancyTreatmentRouteHandler } from "./pregnancy_treatments.ts";
import { ApiError } from "./validation.ts";

const accountId = "11111111-1111-4111-8111-111111111111";
const personId = "22222222-2222-4222-8222-222222222222";
const episodeId = "33333333-3333-4333-8333-333333333333";
const appUserId = "88888888-8888-4888-8888-888888888888";

function request(query = "fromDate=2026-09-11&toDate=2026-09-18") {
  return new Request(
    `https://example.test/api/v1/cocoon/pregnancy/treatments?${query}`,
  );
}

function dependencies(overrides: Record<string, unknown> = {}) {
  return {
    resolveIdentity: async () => ({ accountId, personId }),
    currentEpisode: async () => ({ id: episodeId, status: "active" }),
    requireMedicationRead: async () => {},
    listTreatmentPlans: async () => [
      { id: "44444444-4444-4444-8444-444444444444", status: "active" },
      { id: "55555555-5555-4555-8555-555555555555", status: "archived" },
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
    ...overrides,
  };
}

Deno.test("pregnancy treatment context returns only active canonical treatment data", async () => {
  const authorizationCalls: Array<Record<string, string>> = [];
  const handler = createPregnancyTreatmentRouteHandler("unused", dependencies({
    requireMedicationRead: async (args: Record<string, string>) => {
      authorizationCalls.push(args);
    },
  }));

  const response = await handler({
    request: request(),
    path: "/api/v1/cocoon/pregnancy/treatments",
    appUserId,
  });
  const body = await response!.json();

  assertEquals(response!.status, 200);
  assertEquals(body.contractVersion, 1);
  assertEquals(body.episodeId, episodeId);
  assertEquals(body.mutationAuthority, "canonical_treatment_api");
  assertEquals(body.treatmentPlans.map((value: { id: string }) => value.id), [
    "44444444-4444-4444-8444-444444444444",
  ]);
  assertEquals(
    body.doseOccurrences.map((value: { id: string }) => value.id),
    ["66666666-6666-4666-8666-666666666666"],
  );
  assertEquals(authorizationCalls, [{
    callerAccountId: accountId,
    subjectPersonId: personId,
    episodeId,
  }]);
});

Deno.test("pregnancy treatment route ignores unrelated methods and paths", async () => {
  const handler = createPregnancyTreatmentRouteHandler("unused", dependencies());
  assertEquals(await handler({
    request: new Request(
      "https://example.test/api/v1/cocoon/pregnancy/treatments",
      { method: "POST" },
    ),
    path: "/api/v1/cocoon/pregnancy/treatments",
    appUserId,
  }), null);
  assertEquals(await handler({
    request: request(),
    path: "/api/v1/cocoon/pregnancy/other",
    appUserId,
  }), null);
});

Deno.test("pregnancy treatment context validates required dates and bounded range", async () => {
  const handler = createPregnancyTreatmentRouteHandler("unused", dependencies());

  const missing = await assertRejects(
    () => handler({
      request: request("toDate=2026-09-18"),
      path: "/api/v1/cocoon/pregnancy/treatments",
      appUserId,
    }),
    ApiError,
  );
  assertEquals(missing.status, 400);
  assertEquals(missing.code, "invalid_fromDate");

  const invalidDate = await assertRejects(
    () => handler({
      request: request("fromDate=2026-02-30&toDate=2026-03-01"),
      path: "/api/v1/cocoon/pregnancy/treatments",
      appUserId,
    }),
    ApiError,
  );
  assertEquals(invalidDate.code, "invalid_fromDate");

  const oversized = await assertRejects(
    () => handler({
      request: request("fromDate=2026-09-01&toDate=2026-10-03"),
      path: "/api/v1/cocoon/pregnancy/treatments",
      appUserId,
    }),
    ApiError,
  );
  assertEquals(oversized.code, "invalid_date_range");
});

Deno.test("pregnancy treatment context requires an active episode", async () => {
  for (const episode of [
    null,
    { id: episodeId, status: "ended" },
    { id: "", status: "active" },
  ]) {
    const handler = createPregnancyTreatmentRouteHandler("unused", dependencies({
      currentEpisode: async () => episode,
    }));
    const error = await assertRejects(
      () => handler({
        request: request(),
        path: "/api/v1/cocoon/pregnancy/treatments",
        appUserId,
      }),
      ApiError,
    );
    assertEquals(error.status, 409);
    assertEquals(error.code, "active_pregnancy_required");
  }
});

Deno.test("pregnancy treatment authorization fails closed before canonical data reads", async () => {
  let plansRead = 0;
  let dosesRead = 0;
  const handler = createPregnancyTreatmentRouteHandler("unused", dependencies({
    requireMedicationRead: async () => {
      throw new ApiError(403, "pregnancy_scope_required", "denied");
    },
    listTreatmentPlans: async () => {
      plansRead += 1;
      return [];
    },
    listDoseOccurrences: async () => {
      dosesRead += 1;
      return [];
    },
  }));

  const error = await assertRejects(
    () => handler({
      request: request(),
      path: "/api/v1/cocoon/pregnancy/treatments",
      appUserId,
    }),
    ApiError,
  );
  assertEquals(error.status, 403);
  assertEquals(error.code, "pregnancy_scope_required");
  assertEquals(plansRead, 0);
  assertEquals(dosesRead, 0);
});

Deno.test("pregnancy treatment context returns a truthful empty canonical state", async () => {
  const handler = createPregnancyTreatmentRouteHandler("unused", dependencies({
    listTreatmentPlans: async () => [],
    listDoseOccurrences: async () => [{
      id: "66666666-6666-4666-8666-666666666666",
      treatmentPlanId: "99999999-9999-4999-8999-999999999999",
      status: "scheduled",
    }],
  }));

  const response = await handler({
    request: request(),
    path: "/api/v1/cocoon/pregnancy/treatments",
    appUserId,
  });
  const body = await response!.json();
  assertEquals(body.treatmentPlans, []);
  assertEquals(body.doseOccurrences, []);
});

Deno.test("pregnancy treatment canonical dependency failures propagate", async () => {
  const handler = createPregnancyTreatmentRouteHandler("unused", dependencies({
    listTreatmentPlans: async () => {
      throw new Error("canonical treatment store unavailable");
    },
  }));

  const error = await assertRejects(
    () => handler({
      request: request(),
      path: "/api/v1/cocoon/pregnancy/treatments",
      appUserId,
    }),
    Error,
  );
  assertEquals(error.message, "canonical treatment store unavailable");
});

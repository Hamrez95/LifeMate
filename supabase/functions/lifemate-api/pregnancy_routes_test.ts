import { assertEquals, assertThrows } from "jsr:@std/assert@1.0.14";
import { ApiError } from "./validation.ts";
import {
  mapPregnancyStoreError,
  pregnancyEpisodeReadModel,
} from "./pregnancy_routes.ts";
import {
  type PregnancyEpisode,
  PregnancyStoreError,
} from "./pregnancy_store.ts";

const episode: PregnancyEpisode = {
  id: "11111111-1111-4111-8111-111111111111",
  motherPersonId: "22222222-2222-4222-8222-222222222222",
  status: "active",
  datingMethod: "lmp",
  lmpDate: "2026-07-01",
  estimatedDueDate: null,
  datingReferenceDate: null,
  gestationalAgeAtReferenceDays: null,
  outcome: null,
  activatedAtUtc: "2026-07-01T00:00:00.000Z",
  endedAtUtc: null,
  version: 3,
  createdAtUtc: "2026-07-01T00:00:00.000Z",
  updatedAtUtc: "2026-08-01T00:00:00.000Z",
};

Deno.test("pregnancy read model derives gestational age without mutable week", () => {
  const value = pregnancyEpisodeReadModel(episode, "2026-08-12");
  assertEquals(value.status, "active");
  const dating = value.dating as Record<string, unknown>;
  assertEquals(dating.gestationalAge, {
    totalDays: 42,
    week: 6,
    day: 0,
    basis: "lmp",
  });
  assertEquals("currentWeek" in value, false);
});

Deno.test("pregnancy store conflicts map to stable safe API errors", () => {
  const thrown = assertThrows(
    () =>
      mapPregnancyStoreError(
        new PregnancyStoreError("pregnancy_version_conflict"),
      ),
    ApiError,
  );
  assertEquals(thrown.status, 409);
  assertEquals(thrown.code, "pregnancy_version_conflict");
  assertEquals(thrown.message, "Pregnancy state has changed.");
});

Deno.test("unknown store failures never expose provider detail", () => {
  const thrown = assertThrows(
    () =>
      mapPregnancyStoreError(new PregnancyStoreError("postgres-secret-detail")),
    ApiError,
  );
  assertEquals(thrown.status, 500);
  assertEquals(thrown.code, "pregnancy_operation_failed");
  assertEquals(thrown.message, "Pregnancy request could not be completed.");
});

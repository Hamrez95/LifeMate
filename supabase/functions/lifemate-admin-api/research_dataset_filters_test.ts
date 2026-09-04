import { assertEquals, assertThrows } from "jsr:@std/assert@1.0.14";
import { parseResearchDatasetFilters } from "./research_dataset_filters.ts";

Deno.test("research health observation filters are normalized", () => {
  assertEquals(
    parseResearchDatasetFilters("HealthObservationAggregate", {
      observationTypes: ["weight", "blood_pressure", "weight"],
      observedFrom: "2026-01-01",
      observedTo: "2026-08-01",
      ageMin: 20,
      ageMax: 60,
      homeRegions: ["IR-07", "IR-01"],
    }),
    {
      observationTypes: ["blood_pressure", "weight"],
      observedFrom: "2026-01-01",
      observedTo: "2026-08-01",
      ageMin: 20,
      ageMax: 60,
      homeRegions: ["IR-01", "IR-07"],
    },
  );
});

Deno.test("research filter vocabulary rejects raw/private fields", () => {
  assertThrows(() =>
    parseResearchDatasetFilters("HealthObservationAggregate", {
      note: ["private text"],
    })
  );
  assertThrows(() =>
    parseResearchDatasetFilters("WomenCycleAggregate", {
      privateNotes: ["secret"],
    })
  );
  assertThrows(() =>
    parseResearchDatasetFilters("TreatmentAggregate", {
      medicationName: ["drug"],
    })
  );
});

Deno.test("research filter dates require real calendar dates", () => {
  assertThrows(() =>
    parseResearchDatasetFilters("HealthObservationAggregate", {
      observedFrom: "2026-02-30",
    })
  );
  assertThrows(() =>
    parseResearchDatasetFilters("WomenCycleAggregate", {
      loggedFrom: "2025-02-29",
    })
  );
  assertEquals(
    parseResearchDatasetFilters("WomenCycleAggregate", {
      loggedFrom: "2024-02-29",
    }),
    { loggedFrom: "2024-02-29" },
  );
});

Deno.test("research filter ranges fail closed", () => {
  assertThrows(() =>
    parseResearchDatasetFilters("DoseAdherenceAggregate", {
      ageMin: 50,
      ageMax: 20,
    })
  );
  assertThrows(() =>
    parseResearchDatasetFilters("WomenCycleAggregate", {
      loggedFrom: "2026-08-20",
      loggedTo: "2026-08-01",
    })
  );
});

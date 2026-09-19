import { assertEquals } from "jsr:@std/assert@1.0.14";

Deno.test("all pregnancy unit tests are executed and type-checked by canonical tasks", async () => {
  const config = JSON.parse(await Deno.readTextFile("deno.json")) as {
    tasks?: Record<string, string>;
  };
  const testTask = config.tasks?.test ?? "";
  const checkTask = config.tasks?.check ?? "";
  const pregnancyUnitTests: string[] = [];

  for await (const entry of Deno.readDir(".")) {
    if (
      entry.isFile &&
      /^pregnancy_.*_test\.ts$/.test(entry.name) &&
      !entry.name.endsWith("_integration_test.ts")
    ) {
      pregnancyUnitTests.push(entry.name);
    }
  }
  pregnancyUnitTests.sort();

  const missingFromTest = pregnancyUnitTests.filter((name) =>
    !testTask.split(/\s+/).includes(name)
  );
  const missingFromCheck = pregnancyUnitTests.filter((name) =>
    !checkTask.split(/\s+/).includes(name)
  );

  assertEquals(
    missingFromTest,
    [],
    `Pregnancy unit tests missing from deno task test: ${
      missingFromTest.join(", ")
    }`,
  );
  assertEquals(
    missingFromCheck,
    [],
    `Pregnancy unit tests missing from deno task check: ${
      missingFromCheck.join(", ")
    }`,
  );
});

Deno.test("all pregnancy integration tests are type-checked and executed by the canonical DB task", async () => {
  const config = JSON.parse(await Deno.readTextFile("deno.json")) as {
    tasks?: Record<string, string>;
  };
  const integrationTask = config.tasks?.["test:integration"] ?? "";
  const checkTask = config.tasks?.check ?? "";
  const pregnancyIntegrationTests: string[] = [];

  for await (const entry of Deno.readDir(".")) {
    if (
      entry.isFile &&
      /^pregnancy_.*_integration_test\.ts$/.test(entry.name)
    ) {
      pregnancyIntegrationTests.push(entry.name);
    }
  }
  pregnancyIntegrationTests.sort();

  const missingFromIntegration = pregnancyIntegrationTests.filter((name) =>
    !integrationTask.split(/\s+/).includes(name)
  );
  const missingFromCheck = pregnancyIntegrationTests.filter((name) =>
    !checkTask.split(/\s+/).includes(name)
  );

  assertEquals(
    missingFromIntegration,
    [],
    `Pregnancy integration tests missing from deno task test:integration: ${
      missingFromIntegration.join(", ")
    }`,
  );
  assertEquals(
    missingFromCheck,
    [],
    `Pregnancy integration tests missing from deno task check: ${
      missingFromCheck.join(", ")
    }`,
  );
});

import { assertEquals } from "jsr:@std/assert@1.0.14";

Deno.test("all LifeMate API unit tests are type-checked and executed by canonical tasks", async () => {
  const config = JSON.parse(await Deno.readTextFile("deno.json")) as {
    tasks?: Record<string, string>;
  };
  const testTask = config.tasks?.test ?? "";
  const checkTask = config.tasks?.check ?? "";
  const unitTests: string[] = [];
  const integrationTests: string[] = [];

  for await (const entry of Deno.readDir(".")) {
    if (!entry.isFile || !entry.name.endsWith("_test.ts")) continue;
    if (entry.name.endsWith("_integration_test.ts")) {
      integrationTests.push(entry.name);
    } else {
      unitTests.push(entry.name);
    }
  }
  unitTests.sort();
  integrationTests.sort();

  const executableIntegrationTokens = new Set<string>();
  for (const command of Object.values(config.tasks ?? {})) {
    if (!command.includes("deno test")) continue;
    for (const token of command.split(/\s+/).filter(Boolean)) {
      executableIntegrationTokens.add(token);
    }
  }

  const rawTestTokens = testTask.split(/\s+/).filter(Boolean);
  const rawCheckTokens = checkTask.split(/\s+/).filter(Boolean);
  const testTokens = new Set(rawTestTokens);
  const checkTokens = new Set(rawCheckTokens);

  assertEquals(
    rawTestTokens.length,
    testTokens.size,
    "deno task test must not contain duplicate file entries.",
  );
  assertEquals(
    rawCheckTokens.length,
    checkTokens.size,
    "deno task check must not contain duplicate file entries.",
  );
  assertEquals(
    unitTests.filter((name) => !testTokens.has(name)),
    [],
    "LifeMate API unit tests must be executed by deno task test.",
  );
  assertEquals(
    unitTests.filter((name) => !checkTokens.has(name)),
    [],
    "LifeMate API unit tests must be type-checked by deno task check.",
  );
  assertEquals(
    integrationTests.filter((name) => !executableIntegrationTokens.has(name)),
    [],
    "LifeMate API integration tests must be executed by at least one canonical deno test task.",
  );
  assertEquals(
    integrationTests.filter((name) => !checkTokens.has(name)),
    [],
    "LifeMate API integration tests must be type-checked by deno task check.",
  );
});

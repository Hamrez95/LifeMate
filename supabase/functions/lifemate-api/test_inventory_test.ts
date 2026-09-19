import { assertEquals } from "jsr:@std/assert@1.0.14";

Deno.test("all LifeMate API unit tests are type-checked and executed by canonical tasks", async () => {
  const config = JSON.parse(await Deno.readTextFile("deno.json")) as {
    tasks?: Record<string, string>;
  };
  const testTask = config.tasks?.test ?? "";
  const checkTask = config.tasks?.check ?? "";
  const unitTests: string[] = [];

  for await (const entry of Deno.readDir(".")) {
    if (
      entry.isFile &&
      entry.name.endsWith("_test.ts") &&
      !entry.name.endsWith("_integration_test.ts")
    ) {
      unitTests.push(entry.name);
    }
  }
  unitTests.sort();

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
});

import { assertEquals } from "jsr:@std/assert@1.0.14";

Deno.test("all Care Management unit tests are type-checked and executed", async () => {
  const config = JSON.parse(await Deno.readTextFile("deno.json")) as {
    tasks?: Record<string, string>;
  };
  const rawTestTokens = (config.tasks?.test ?? "").split(/\s+/).filter(Boolean);
  const rawCheckTokens = (config.tasks?.check ?? "").split(/\s+/).filter(Boolean);
  const testTokens = new Set(rawTestTokens);
  const checkTokens = new Set(rawCheckTokens);
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
    "Care Management unit tests must be executed by deno task test.",
  );
  assertEquals(
    unitTests.filter((name) => !checkTokens.has(name)),
    [],
    "Care Management unit tests must be type-checked by deno task check.",
  );
});

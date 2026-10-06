import { assertEquals } from "jsr:@std/assert@1.0.14";

Deno.test("service unit tests stay wired into canonical check and test tasks", async () => {
  const config = JSON.parse(
    await Deno.readTextFile(new URL("./deno.json", import.meta.url)),
  ) as { tasks?: Record<string, string> };
  const checkTokens = new Set(
    (config.tasks?.check ?? "").split(/\s+/).filter(Boolean),
  );
  const rawTestTokens = (config.tasks?.test ?? "").split(/\s+/).filter(Boolean);
  const testTokens = new Set(rawTestTokens);
  const tests: string[] = [];

  for await (const entry of Deno.readDir(".")) {
    if (
      entry.isFile &&
      entry.name.endsWith("_test.ts") &&
      !entry.name.endsWith("_integration_test.ts")
    ) {
      tests.push(entry.name);
    }
  }
  tests.sort();

  assertEquals(
    rawTestTokens.length,
    testTokens.size,
    "deno task test must not contain duplicate file entries.",
  );
  assertEquals(
    tests.filter((name) => !testTokens.has(name)),
    [],
    "Unit tests must be executed by deno task test.",
  );
  assertEquals(
    tests.filter((name) => !checkTokens.has(name)),
    [],
    "Unit tests must be type-checked by deno task check.",
  );
  assertEquals(
    checkTokens.has("index.ts"),
    true,
    "Production entrypoint must stay in deno task check.",
  );
});

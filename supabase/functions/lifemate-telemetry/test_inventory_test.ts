import { assertEquals } from "jsr:@std/assert@1.0.14";

Deno.test("Telemetry unit tests stay wired into canonical check and test tasks", async () => {
  const config = JSON.parse(
    await Deno.readTextFile(new URL("./deno.json", import.meta.url)),
  ) as { tasks?: Record<string, string> };
  const checkTokens = new Set(
    (config.tasks?.check ?? "").split(/\s+/).filter(Boolean),
  );
  const testCommand = config.tasks?.test ?? "";
  const rawTestTokens = testCommand.split(/\s+/).filter(Boolean);
  const testTokens = new Set(rawTestTokens);

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
    unitTests.filter((name) => !testTokens.has(name)),
    [],
    "Telemetry unit tests must be executed by deno task test.",
  );
  assertEquals(
    unitTests.filter((name) => !checkTokens.has(name)),
    [],
    "Telemetry unit tests must be type-checked by deno task check.",
  );
  assertEquals(
    checkTokens.has("index.ts"),
    true,
    "Telemetry production entrypoint must stay in deno task check.",
  );
});

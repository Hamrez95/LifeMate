import { assertEquals } from "jsr:@std/assert@1.0.14";

Deno.test("Readiness tests stay wired into canonical execution tasks", async () => {
  const config = JSON.parse(
    await Deno.readTextFile(new URL("./deno.json", import.meta.url)),
  ) as { tasks?: Record<string, string> };
  const checkTokens = new Set(
    (config.tasks?.check ?? "").split(/\s+/).filter(Boolean),
  );
  const executionTokens = new Set<string>();
  for (const taskName of ["test", "test:integration"]) {
    for (
      const token of (config.tasks?.[taskName] ?? "").split(/\s+/).filter(Boolean)
    ) {
      executionTokens.add(token);
    }
  }

  const tests: string[] = [];
  for await (const entry of Deno.readDir(".")) {
    if (entry.isFile && entry.name.endsWith("_test.ts")) tests.push(entry.name);
  }
  tests.sort();

  assertEquals(
    tests.filter((name) => !executionTokens.has(name)),
    [],
    "Readiness tests must be executed by a canonical test task.",
  );
  assertEquals(
    tests.filter((name) => !checkTokens.has(name)),
    [],
    "Readiness tests must be type-checked by deno task check.",
  );
  assertEquals(
    checkTokens.has("index.ts"),
    true,
    "Readiness production entrypoint must stay in deno task check.",
  );
});

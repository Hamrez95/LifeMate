import { assert, assertStringIncludes } from "jsr:@std/assert";

Deno.test("relationship overview does not require a nonexistent access_grants version column", async () => {
  const source = await Deno.readTextFile(
    new URL("./relationship_overview_store.ts", import.meta.url),
  );

  assertStringIncludes(source, "from security.access_grants g");
  assertStringIncludes(source, "null::integer as version");
  assert(!source.includes("g.version"));
});

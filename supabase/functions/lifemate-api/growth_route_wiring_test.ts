import { assertStringIncludes } from "jsr:@std/assert";

Deno.test("LifeMate API dispatches canonical growth routes after authenticated identity resolution", async () => {
  const index = await Deno.readTextFile(new URL("./index.ts", import.meta.url));

  assertStringIncludes(index, 'import { createGrowthRouteHandler } from "./growth_routes.ts";');
  assertStringIncludes(index, "createGrowthRouteHandler(databaseUrl, contactHashingSecret)");
  assertStringIncludes(index, 'path.startsWith("/api/v1/growth/")');
  assertStringIncludes(index, "appUserId: identity.appUserId");
  assertStringIncludes(index, "if (growthResponse) return growthResponse;");
}

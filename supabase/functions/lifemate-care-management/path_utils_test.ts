import { assertEquals } from "jsr:@std/assert@1";
import { normalizeCareManagementPath } from "./path_utils.ts";

Deno.test("normalizes production care management path", () => {
  assertEquals(
    normalizeCareManagementPath(
      "/functions/v1/lifemate-care-management/api/v1/relationships/abc",
    ),
    "/api/v1/relationships/abc",
  );
});

Deno.test("normalizes candidate care management path", () => {
  assertEquals(
    normalizeCareManagementPath(
      "/functions/v1/lifemate-care-management-candidate/api/v1/relationships/abc",
    ),
    "/api/v1/relationships/abc",
  );
});

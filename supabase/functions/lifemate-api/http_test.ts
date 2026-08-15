import { assertEquals } from "jsr:@std/assert@1.0.14";
import { safeError } from "./http.ts";
import { ApiError } from "./validation.ts";

Deno.test("safeError never copies generic exception messages into logs", () => {
  const safe = safeError(
    new Error("patient@example.test Bearer secret medication=private"),
  );
  assertEquals(safe.name, "Error");
  assertEquals("message" in safe, false);
});

Deno.test("safeError keeps bounded API status/code without detail", () => {
  const safe = safeError(
    new ApiError(409, "database_conflict", "private patient detail"),
  );
  assertEquals(safe, {
    name: "ApiError",
    code: "database_conflict",
    status: 409,
  });
  assertEquals("message" in safe, false);
});

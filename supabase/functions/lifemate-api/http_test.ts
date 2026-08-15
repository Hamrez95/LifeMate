import { assertEquals } from "jsr:@std/assert@1.0.14";
import { problem, safeError } from "./http.ts";
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

Deno.test("database pressure response is controlled and carries Retry-After", async () => {
  const response = problem(
    503,
    "database_busy",
    "The healthcare database is temporarily unavailable. Retry shortly.",
    "123e4567-e89b-42d3-a456-426614174888",
  );
  assertEquals(response.status, 503);
  assertEquals(response.headers.get("Retry-After"), "2");
  assertEquals(response.headers.get("Cache-Control"), "no-store");
  const body = await response.json();
  assertEquals(body.code, "database_busy");
  assertEquals(body.status, 503);
  assertEquals(
    body.correlationId,
    "123e4567-e89b-42d3-a456-426614174888",
  );
});

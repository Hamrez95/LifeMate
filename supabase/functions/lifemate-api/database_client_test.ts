import { assert } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { isPostgresUnavailable } from "./database_client.ts";

Deno.test("connection exhaustion is returned as retryable unavailability", () => {
  assert(isPostgresUnavailable({ code: "53300", message: "too many clients" }));
  assert(
    isPostgresUnavailable({
      message:
        "remaining connection slots are reserved for roles with the SUPERUSER attribute",
    }),
  );
  assert(!isPostgresUnavailable({ code: "23505", message: "duplicate key" }));
});

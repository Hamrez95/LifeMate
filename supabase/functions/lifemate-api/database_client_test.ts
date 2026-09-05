import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  isPostgresUnavailable,
  lifeMateDatabaseClientOptions,
} from "./database_client.ts";

Deno.test("connection exhaustion and query pressure are retryable unavailability", () => {
  assert(isPostgresUnavailable({ code: "53300", message: "too many clients" }));
  assert(
    isPostgresUnavailable({
      message:
        "remaining connection slots are reserved for roles with the SUPERUSER attribute",
    }),
  );
  assert(
    isPostgresUnavailable({ code: "57014", message: "statement timeout" }),
  );
  assert(
    isPostgresUnavailable({
      code: "55P03",
      message: "canceling statement due to lock timeout",
    }),
  );
  assert(!isPostgresUnavailable({ code: "23505", message: "duplicate key" }));
});

Deno.test("Edge database client uses one bounded connection and query timeouts", () => {
  const options = lifeMateDatabaseClientOptions("lifemate-api-test");
  assertEquals(options.max, 1);
  assertEquals(options.prepare, false);
  assertEquals(options.idle_timeout, 5);
  assertEquals(options.connect_timeout, 10);
  assertEquals(options.max_lifetime, 600);
  assertEquals(options.connection.application_name, "lifemate-api-test");
  assertEquals(options.connection.statement_timeout, 5000);
  assertEquals(options.connection.lock_timeout, 2000);
  assertEquals(options.connection.idle_in_transaction_session_timeout, 15000);
});

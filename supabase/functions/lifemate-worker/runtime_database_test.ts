import {
  assert,
  assertEquals,
} from "jsr:@std/assert@1";
import {
  buildWorkerDatabaseUrl,
  isRestrictedWorkerDatabaseUrl,
} from "./runtime_database.ts";

Deno.test("worker database URL accepts only the restricted runtime role", () => {
  assert(isRestrictedWorkerDatabaseUrl(
    "postgres://lifemate_worker_runtime:secret@example.test/postgres",
  ));
  assert(isRestrictedWorkerDatabaseUrl(
    "postgres://lifemate_worker_runtime.projectref:secret@example.test/postgres",
  ));
  assertEquals(
    isRestrictedWorkerDatabaseUrl(
      "postgres://postgres.projectref:secret@example.test/postgres",
    ),
    false,
  );
  assertEquals(
    isRestrictedWorkerDatabaseUrl("not-a-database-url"),
    false,
  );
});

Deno.test("bootstrap URL is rewritten to the restricted worker role", () => {
  const result = new URL(buildWorkerDatabaseUrl(
    "postgres://postgres.projectref:bootstrap@example.test/postgres",
    "0123456789abcdef0123456789abcdef",
  ));

  assertEquals(
    decodeURIComponent(result.username),
    "lifemate_worker_runtime.projectref",
  );
  assertEquals(
    decodeURIComponent(result.password),
    "0123456789abcdef0123456789abcdef",
  );
});

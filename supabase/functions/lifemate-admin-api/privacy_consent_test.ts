import { assertEquals, assertRejects } from "jsr:@std/assert@1";
import {
  createPrivacyConsentRouteHandler,
  parseDirectoryQuery,
} from "./privacy_consent_routes.ts";
import { ApiError } from "./validation.ts";

Deno.test("privacy directory rejects unsupported lifecycle status", () => {
  try {
    parseDirectoryQuery(
      new URL("https://admin.test/api/v1/privacy/documents?status=Deleted"),
      "document",
    );
    throw new Error("expected rejection");
  } catch (error) {
    assertEquals((error as ApiError).status, 400);
    assertEquals((error as ApiError).code, "privacy_status_invalid");
  }
});

Deno.test("privacy mutation is permission scoped before database access", async () => {
  const handler = createPrivacyConsentRouteHandler("postgres://unused");
  await assertRejects(
    () =>
      handler({
        request: new Request("https://admin.test/api/v1/privacy/documents", {
          method: "POST",
          headers: { "Idempotency-Key": "privacy-test-123" },
          body: "{}",
        }),
        path: "/api/v1/privacy/documents",
        accountId: "11111111-1111-4111-8111-111111111111",
        admin: {
          accountId: "11111111-1111-4111-8111-111111111111",
          roles: [],
          permissions: ["privacy.consent.read"],
        },
        correlationId: "22222222-2222-4222-8222-222222222222",
        origin: null,
      }),
    ApiError,
    "Administrative permission is required",
  );
});

Deno.test("privacy mutation requires idempotency key before database access", async () => {
  const handler = createPrivacyConsentRouteHandler("postgres://unused");
  await assertRejects(
    () =>
      handler({
        request: new Request("https://admin.test/api/v1/privacy/documents", {
          method: "POST",
          body: "{}",
        }),
        path: "/api/v1/privacy/documents",
        accountId: "11111111-1111-4111-8111-111111111111",
        admin: {
          accountId: "11111111-1111-4111-8111-111111111111",
          roles: ["founder"],
          permissions: ["privacy.consent.read", "privacy.consent.manage"],
        },
        correlationId: "22222222-2222-4222-8222-222222222222",
        origin: null,
      }),
    ApiError,
  );
});

Deno.test("privacy contract exposes no admin acceptance or user opt-in mutation", async () => {
  const source = await Deno.readTextFile(
    new URL("./privacy_consent_routes.ts", import.meta.url),
  );
  assertEquals(source.includes("acceptances/accept"), false);
  assertEquals(source.includes("consents/grant"), false);
  assertEquals(source.includes("preferences/opt-in"), false);
  assertEquals(
    source.includes("accountPreferenceMutableFromAdmin:false"),
    true,
  );
});

Deno.test("preference-purpose policy directory is admin-runtime only and uses policy timestamps", async () => {
  const migration = await Deno.readTextFile(
    new URL(
      "../../migrations/20260828094000_admin_preference_purpose_policy_directory.sql",
      import.meta.url,
    ),
  );
  assertEquals(migration.includes("from consent.preference_purposes p"), true);
  assertEquals(migration.includes("p.updated_at_utc"), true);
  assertEquals(migration.includes("consent.data_use_consents"), false);
  assertEquals(
    migration.includes(
      "grant select on consent.admin_preference_purpose_policy_directory_v1 to lifemate_admin_runtime",
    ),
    true,
  );
  assertEquals(
    migration.includes("array['anon','authenticated','lifemate_edge_runtime']"),
    true,
  );
});

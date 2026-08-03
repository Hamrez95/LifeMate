import { assertEquals, assertRejects } from "jsr:@std/assert@1.0.14";
import postgres from "postgres";
import {
  type AuthUser,
  createLifeMateDatabase,
} from "./database.ts";
import { createProfileStore } from "./profile.ts";
import { ApiError } from "./validation.ts";

const databaseUrl = Deno.env.get("TEST_DATABASE_URL");
if (!databaseUrl) {
  throw new Error(
    "TEST_DATABASE_URL is required for profile integration tests.",
  );
}

Deno.test({
  name: "profile edits persist with optimistic concurrency and redacted audit",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
    const admin = postgres(databaseUrl, { max: 1, prepare: false });
    const db = createLifeMateDatabase(
      databaseUrl,
      "integration-only-profile-contact-secret-32-bytes-minimum",
    );
    const profiles = createProfileStore(databaseUrl);
    const suffix = crypto.randomUUID();
    const auth: AuthUser = {
      id: `profile-${suffix}`,
      email: `profile-${suffix}@example.test`,
      phone: null,
      userMetadata: {},
    };

    try {
      await db.bootstrapUser(auth, {
        displayName: "نام اولیه",
        locale: "fa",
        timeZone: "Asia/Tehran",
      });
      const identity = await db.requireIdentity(auth);

      const initial = await profiles.getProfile(identity.appUserId);
      assertEquals(initial.version, 1);
      assertEquals(initial.displayName, "نام اولیه");

      const updated = await profiles.updateProfile(identity.appUserId, auth, {
        version: 1,
        displayName: "نام ویرایش‌شده",
        phoneNumber: "+98 (912) 123-4567",
        locale: "fa",
        timeZone: "Europe/Berlin",
      });
      assertEquals(updated.version, 2);
      assertEquals(updated.displayName, "نام ویرایش‌شده");
      assertEquals(updated.phoneNumber, "+989121234567");
      assertEquals(updated.email, auth.email);
      assertEquals(updated.timeZone, "Europe/Berlin");

      const stale = await assertRejects(
        () =>
          profiles.updateProfile(identity.appUserId, auth, {
            version: 1,
            displayName: "ویرایش قدیمی",
            phoneNumber: null,
            locale: "fa",
            timeZone: "Asia/Tehran",
          }),
        ApiError,
      );
      assertEquals(stale.status, 409);
      assertEquals(stale.code, "stale_profile");

      const reconnected = createProfileStore(databaseUrl);
      const persisted = await reconnected.getProfile(identity.appUserId);
      assertEquals(persisted.version, 2);
      assertEquals(persisted.displayName, "نام ویرایش‌شده");

      const audits = await admin`
        select action, resource_type, metadata_json
        from lifemate.audit_logs
        where actor_user_id = ${identity.appUserId}
          and action = 'profile.updated'
      `;
      assertEquals(audits.length, 1);
      assertEquals(audits[0].resource_type, "user_profile");
      assertEquals(audits[0].metadata_json, null);
    } finally {
      await admin.end({ timeout: 5 });
    }
  },
});

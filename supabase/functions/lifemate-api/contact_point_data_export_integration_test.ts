import { assertEquals, assertRejects } from "jsr:@std/assert@1.0.14";
import postgres from "postgres";
import { createContactPointWriter } from "./contact_points.ts";
import { createDataExportStore } from "./data_export.ts";
import { type AuthUser, createLifeMateDatabase } from "./database.ts";
import { ApiError } from "./validation.ts";

const databaseUrl = Deno.env.get("TEST_DATABASE_URL");
if (!databaseUrl) {
  throw new Error(
    "TEST_DATABASE_URL is required for ContactPoint data-export integration tests.",
  );
}

const envNames = [
  "LIFEMATE_PROFILE_CONTACT_LOOKUP_MODE",
  "LIFEMATE_IDENTITY_CONTACT_ENCRYPTION_KEY",
  "LIFEMATE_IDENTITY_CONTACT_ENCRYPTION_KEY_VERSION",
  "LIFEMATE_IDENTITY_CONTACT_READINESS_APPROVED",
  "LIFEMATE_IDENTITY_CONTACT_RAW_RETIREMENT",
  "LIFEMATE_IDENTITY_CONTACT_DUAL_WRITE",
] as const;

Deno.test({
  name:
    "self-service export uses encrypted ContactPoints after raw Profile contact retirement",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
    const admin = postgres(databaseUrl, { max: 1, prepare: false });
    const previous = new Map<string, string | undefined>();
    for (const name of envNames) previous.set(name, Deno.env.get(name));

    const hashingSecret = "contact-export-integration-hash-secret-32-bytes";
    const encryptionKey = {
      secret: "contact-export-integration-envelope-key-32-bytes",
      keyVersion: 41,
    };
    const email = `contact-export-${crypto.randomUUID()}@example.test`;
    const phone = "+989121112233";
    const auth: AuthUser = {
      id: `contact-export-${crypto.randomUUID()}`,
      email,
      phone: null,
      userMetadata: {},
    };
    let appUserId: string | null = null;
    let accountId: string | null = null;

    try {
      Deno.env.set("LIFEMATE_PROFILE_CONTACT_LOOKUP_MODE", "legacy");
      Deno.env.set("LIFEMATE_IDENTITY_CONTACT_DUAL_WRITE", "false");
      Deno.env.set("LIFEMATE_IDENTITY_CONTACT_RAW_RETIREMENT", "false");
      Deno.env.set("LIFEMATE_IDENTITY_CONTACT_READINESS_APPROVED", "false");
      Deno.env.delete("LIFEMATE_IDENTITY_CONTACT_ENCRYPTION_KEY");
      Deno.env.delete("LIFEMATE_IDENTITY_CONTACT_ENCRYPTION_KEY_VERSION");

      const db = createLifeMateDatabase(databaseUrl, hashingSecret);
      await db.bootstrapUser(auth, {
        displayName: "Contact Export",
        locale: "fa",
        timeZone: "Asia/Tehran",
      });
      const identity = await db.requireIdentity(auth);
      appUserId = identity.appUserId;
      const accountRows = await admin`
        select identity.account_id_for_legacy_app_user(${appUserId}::uuid)::text
          as account_id
      `;
      accountId = String(accountRows[0]?.account_id ?? "");

      await admin`
        update lifemate.user_profiles
        set email=${email},phone_number=${phone},updated_at_utc=now()
        where user_id=${appUserId}::uuid
      `;

      const writer = createContactPointWriter(hashingSecret, {
        enabled: true,
        encryptionKey,
      });
      await admin.begin(async (tx) => {
        await writer.syncForAccount(
          tx,
          accountId!,
          { email, phone },
          "replace",
        );
      });

      // Simulate the final retirement state without changing production schema:
      // the portable export must no longer depend on these raw compatibility
      // columns once contact-only is explicitly enabled.
      await admin`
        update lifemate.user_profiles
        set email=null,phone_number=null,updated_at_utc=now()
        where user_id=${appUserId}::uuid
      `;

      Deno.env.set("LIFEMATE_PROFILE_CONTACT_LOOKUP_MODE", "contact-only");
      Deno.env.set("LIFEMATE_IDENTITY_CONTACT_READINESS_APPROVED", "true");
      Deno.env.set("LIFEMATE_IDENTITY_CONTACT_DUAL_WRITE", "true");
      Deno.env.set("LIFEMATE_IDENTITY_CONTACT_RAW_RETIREMENT", "true");
      Deno.env.set(
        "LIFEMATE_IDENTITY_CONTACT_ENCRYPTION_KEY",
        encryptionKey.secret,
      );
      Deno.env.set(
        "LIFEMATE_IDENTITY_CONTACT_ENCRYPTION_KEY_VERSION",
        String(encryptionKey.keyVersion),
      );

      const exporter = createDataExportStore(databaseUrl);
      const exported = await exporter.exportAccountData(appUserId);
      const profile = exported.profile as Record<string, unknown>;
      assertEquals(profile.email, email.toLowerCase());
      assertEquals(profile.phoneNumber, phone);

      const encoded = JSON.stringify(exported);
      assertEquals(encoded.includes(encryptionKey.secret), false);
      const contactRows = await admin`
        select normalized_value_hash,
               encode(encrypted_value,'base64') as ciphertext_b64,
               encryption_nonce_b64
        from identity.contact_points
        where account_id=${accountId}::uuid and status <> 'Revoked'
      `;
      for (const row of contactRows) {
        assertEquals(
          encoded.includes(String(row.normalized_value_hash)),
          false,
        );
        assertEquals(encoded.includes(String(row.ciphertext_b64)), false);
        assertEquals(encoded.includes(String(row.encryption_nonce_b64)), false);
      }

      await admin`
        update identity.contact_points
        set encryption_key_version=${encryptionKey.keyVersion + 1}
        where account_id=${accountId}::uuid
          and kind='Phone' and status <> 'Revoked'
      `;
      const unavailable = await assertRejects(
        () => exporter.exportAccountData(appUserId!),
        ApiError,
      );
      assertEquals(unavailable.status, 503);
      assertEquals(unavailable.code, "contact_point_unavailable");
    } finally {
      if (accountId) {
        await admin`
          delete from identity.contact_points where account_id=${accountId}::uuid
        `.catch(() => undefined);
      }
      if (appUserId) {
        await admin`
          delete from lifemate.audit_logs
          where actor_user_id=${appUserId}::uuid or resource_id=${appUserId}::uuid
        `.catch(() => undefined);
        await admin`
          delete from lifemate.user_profiles where user_id=${appUserId}::uuid
        `.catch(() => undefined);
        await admin`
          delete from identity.external_identity_tokens where account_id=${accountId}::uuid
        `.catch(() => undefined);
        await admin`
          delete from identity.external_identities where account_id=${accountId}::uuid
        `.catch(() => undefined);
        await admin`
          delete from core.account_person_links where account_id=${accountId}::uuid
        `.catch(() => undefined);
        await admin`
          delete from ecosystem.app_enrollments where account_id=${accountId}::uuid
        `.catch(() => undefined);
        await admin`
          delete from identity.accounts where id=${accountId}::uuid
        `.catch(() => undefined);
        await admin`
          delete from lifemate.app_users where id=${appUserId}::uuid
        `.catch(() => undefined);
        await admin`
          delete from core.person_profiles where person_id=${appUserId}::uuid
        `.catch(() => undefined);
        await admin`
          delete from core.persons where id=${appUserId}::uuid
        `.catch(() => undefined);
      }
      for (const name of envNames) {
        const value = previous.get(name);
        if (value === undefined) Deno.env.delete(name);
        else Deno.env.set(name, value);
      }
      await admin.end({ timeout: 5 });
    }
  },
});

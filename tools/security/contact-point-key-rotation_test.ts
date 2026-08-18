import { assertEquals, assertRejects } from "jsr:@std/assert@1.0.14";
import postgres from "npm:postgres@3.4.7";
import {
  createContactPointWriter,
} from "../../supabase/functions/lifemate-api/contact_points.ts";
import { ApiError } from "../../supabase/functions/lifemate-api/validation.ts";
import { rotateContactPointEncryptionKeys } from "./contact-point-key-rotation.ts";

const databaseUrl = Deno.env.get("TEST_DATABASE_URL");
if (!databaseUrl) {
  throw new Error(
    "TEST_DATABASE_URL is required for ContactPoint key-rotation tests.",
  );
}

Deno.test({
  name:
    "ContactPoint envelope rotation dry-run is read-only, apply preserves verification state, rerun is idempotent and unknown versions fail closed",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
    const sql = postgres(databaseUrl, { max: 1, prepare: false });
    const appUserId = crypto.randomUUID();
    const hashingSecret =
      "contact-key-rotation-tool-hash-secret-32-bytes";
    const previousKey = {
      secret: "contact-key-rotation-tool-previous-key-32-bytes",
      keyVersion: 61,
    };
    const activeKey = {
      secret: "contact-key-rotation-tool-active-key-32-bytes",
      keyVersion: 62,
    };
    const verifiedAt = new Date("2026-08-18T12:00:00.000Z");
    let accountId: string | null = null;
    let contactPointId: string | null = null;

    try {
      await sql`
        insert into lifemate.app_users(
          id,auth_subject,status,created_at_utc,updated_at_utc
        ) values(
          ${appUserId}::uuid,${crypto.randomUUID()},'Active',now(),now()
        )
      `;
      const accountRows = await sql`
        select identity.account_id_for_legacy_app_user(${appUserId}::uuid)::text
          as account_id
      `;
      accountId = String(accountRows[0]?.account_id ?? "");

      const writer = createContactPointWriter(hashingSecret, {
        enabled: true,
        encryptionKey: previousKey,
      });
      await sql.begin(async (tx) => {
        await writer.syncForAccount(
          tx,
          accountId!,
          { email: `rotation-tool-${crypto.randomUUID()}@example.test` },
          "replace",
        );
      });
      const created = await sql`
        update identity.contact_points
        set status='Verified',verified_at_utc=${verifiedAt},updated_at_utc=now()
        where account_id=${accountId}::uuid
          and kind='Email' and status <> 'Revoked'
        returning id::text as id,normalized_value_hash,
                  encode(encrypted_value,'base64') as ciphertext_b64,
                  encryption_nonce_b64,encryption_key_version,status,
                  verified_at_utc
      `;
      contactPointId = String(created[0]?.id ?? "");
      const before = created[0];

      const dryRun = await rotateContactPointEncryptionKeys({
        databaseUrl,
        hashingSecret,
        activeEncryptionKey: activeKey.secret,
        activeKeyVersion: activeKey.keyVersion,
        previousEncryptionKey: previousKey.secret,
        previousKeyVersion: previousKey.keyVersion,
        mode: "dry-run",
        maxContacts: 100,
      });
      assertEquals(dryRun.scannedContacts, 1);
      assertEquals(dryRun.activeVersionContacts, 0);
      assertEquals(dryRun.previousVersionContacts, 1);
      assertEquals(dryRun.rotatedContacts, 0);
      assertEquals(dryRun.hasMore, false);
      assertEquals(
        dryRun.nextAfterContactPointId,
        contactPointId,
      );

      const afterDryRun = await envelopeRow(sql, contactPointId);
      assertEquals(afterDryRun, before);

      const applied = await rotateContactPointEncryptionKeys({
        databaseUrl,
        hashingSecret,
        activeEncryptionKey: activeKey.secret,
        activeKeyVersion: activeKey.keyVersion,
        previousEncryptionKey: previousKey.secret,
        previousKeyVersion: previousKey.keyVersion,
        mode: "apply",
        maxContacts: 100,
        confirmation: "ROTATE-CONTACT-ENVELOPES",
      });
      assertEquals(applied.scannedContacts, 1);
      assertEquals(applied.previousVersionContacts, 1);
      assertEquals(applied.rotatedContacts, 1);

      const rotated = await envelopeRow(sql, contactPointId);
      assertEquals(rotated.normalized_value_hash, before.normalized_value_hash);
      assertEquals(rotated.status, "Verified");
      assertEquals(
        new Date(rotated.verified_at_utc).toISOString(),
        verifiedAt.toISOString(),
      );
      assertEquals(Number(rotated.encryption_key_version), activeKey.keyVersion);
      assertEquals(rotated.ciphertext_b64 === before.ciphertext_b64, false);
      assertEquals(
        rotated.encryption_nonce_b64 === before.encryption_nonce_b64,
        false,
      );

      const rerun = await rotateContactPointEncryptionKeys({
        databaseUrl,
        hashingSecret,
        activeEncryptionKey: activeKey.secret,
        activeKeyVersion: activeKey.keyVersion,
        previousEncryptionKey: previousKey.secret,
        previousKeyVersion: previousKey.keyVersion,
        mode: "apply",
        maxContacts: 100,
        confirmation: "ROTATE-CONTACT-ENVELOPES",
      });
      assertEquals(rerun.activeVersionContacts, 1);
      assertEquals(rerun.previousVersionContacts, 0);
      assertEquals(rerun.rotatedContacts, 0);

      await sql`
        update identity.contact_points
        set encryption_key_version=${activeKey.keyVersion + 1}
        where id=${contactPointId}::uuid
      `;
      const unknownBefore = await envelopeRow(sql, contactPointId);
      const unavailable = await assertRejects(
        () =>
          rotateContactPointEncryptionKeys({
            databaseUrl,
            hashingSecret,
            activeEncryptionKey: activeKey.secret,
            activeKeyVersion: activeKey.keyVersion,
            previousEncryptionKey: previousKey.secret,
            previousKeyVersion: previousKey.keyVersion,
            mode: "apply",
            maxContacts: 100,
            confirmation: "ROTATE-CONTACT-ENVELOPES",
          }),
        ApiError,
      );
      assertEquals(unavailable.status, 503);
      assertEquals(unavailable.code, "contact_point_unavailable");
      assertEquals(await envelopeRow(sql, contactPointId), unknownBefore);

      await assertRejects(
        () =>
          rotateContactPointEncryptionKeys({
            databaseUrl,
            hashingSecret,
            activeEncryptionKey: activeKey.secret,
            activeKeyVersion: activeKey.keyVersion,
            previousEncryptionKey: previousKey.secret,
            previousKeyVersion: previousKey.keyVersion,
            mode: "apply",
            maxContacts: 100,
            confirmation: "WRONG",
          }),
        Error,
        "ROTATE-CONTACT-ENVELOPES",
      );
    } finally {
      if (accountId) {
        await sql`
          delete from identity.contact_points where account_id=${accountId}::uuid
        `.catch(() => undefined);
        await sql`
          delete from identity.external_identities where account_id=${accountId}::uuid
        `.catch(() => undefined);
        await sql`
          delete from core.account_person_links where account_id=${accountId}::uuid
        `.catch(() => undefined);
        await sql`
          delete from ecosystem.app_enrollments where account_id=${accountId}::uuid
        `.catch(() => undefined);
        await sql`
          update identity.accounts
          set legacy_app_user_id=null,updated_at_utc=now()
          where id=${accountId}::uuid
        `.catch(() => undefined);
        await sql`
          delete from identity.accounts where id=${accountId}::uuid
        `.catch(() => undefined);
      }
      await sql`
        delete from lifemate.app_users where id=${appUserId}::uuid
      `.catch(() => undefined);
      await sql`
        delete from core.person_profiles where person_id=${appUserId}::uuid
      `.catch(() => undefined);
      await sql`
        delete from core.persons where id=${appUserId}::uuid
      `.catch(() => undefined);
      await sql.end({ timeout: 5 });
    }
  },
});

async function envelopeRow(connection: any, id: string) {
  const rows = await connection`
    select id::text as id,normalized_value_hash,
           encode(encrypted_value,'base64') as ciphertext_b64,
           encryption_nonce_b64,encryption_key_version,status,verified_at_utc
    from identity.contact_points
    where id=${id}::uuid
  `;
  return rows[0];
}

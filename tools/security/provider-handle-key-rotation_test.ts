import { assertEquals, assertRejects } from "jsr:@std/assert@1.0.14";
import postgres from "npm:postgres@3.4.7";
import {
  encryptProviderIdentitySubject,
} from "../../supabase/functions/_shared/provider_identity_handle_crypto.ts";
import { rotateProviderIdentityHandleKeys } from "./provider-handle-key-rotation.ts";

const databaseUrl = Deno.env.get("TEST_DATABASE_URL");
if (!databaseUrl) {
  throw new Error(
    "TEST_DATABASE_URL is required for provider-handle rotation tests.",
  );
}

Deno.test({
  name:
    "provider-handle rotation dry-run is read-only, apply is authenticated/idempotent and unknown versions fail closed",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
    const sql = postgres(databaseUrl, { max: 1, prepare: false });
    const appUserId = crypto.randomUUID();
    const subject = crypto.randomUUID();
    const previousKey = {
      secret: "provider-handle-rotation-previous-key-32-bytes-minimum",
      keyVersion: 91,
    };
    const activeKey = {
      secret: "provider-handle-rotation-active-key-32-bytes-minimum",
      keyVersion: 92,
    };
    let accountId: string | null = null;

    try {
      await sql`
        insert into lifemate.app_users(
          id,auth_subject,status,created_at_utc,updated_at_utc
        ) values(${appUserId}::uuid,${subject},'Active',now(),now())
      `;
      accountId = await accountFor(sql, appUserId);
      const envelope = await encryptProviderIdentitySubject(
        previousKey,
        {
          accountId,
          provider: "supabase_auth",
          issuer: "supabase",
        },
        subject,
        new Uint8Array(12).fill(3),
      );
      await sql`
        insert into identity.provider_identity_handles(
          account_id,provider,issuer,ciphertext_b64,nonce_b64,key_version,
          status,created_at_utc,updated_at_utc
        ) values(
          ${accountId}::uuid,'supabase_auth','supabase',
          ${envelope.ciphertextB64},${envelope.nonceB64},
          ${envelope.keyVersion},'Active',now(),now()
        )
      `;
      const before = await handleRow(sql, accountId);

      const dryRun = await rotateProviderIdentityHandleKeys({
        databaseUrl,
        activeEncryptionKey: activeKey.secret,
        activeKeyVersion: activeKey.keyVersion,
        previousEncryptionKey: previousKey.secret,
        previousKeyVersion: previousKey.keyVersion,
        mode: "dry-run",
        maxHandles: 100,
      });
      assertEquals(dryRun.scannedHandles, 1);
      assertEquals(dryRun.previousVersionHandles, 1);
      assertEquals(dryRun.rotatedHandles, 0);
      assertEquals(await handleRow(sql, accountId), before);

      const applied = await rotateProviderIdentityHandleKeys({
        databaseUrl,
        activeEncryptionKey: activeKey.secret,
        activeKeyVersion: activeKey.keyVersion,
        previousEncryptionKey: previousKey.secret,
        previousKeyVersion: previousKey.keyVersion,
        mode: "apply",
        maxHandles: 100,
        confirmation: "ROTATE-PROVIDER-HANDLES",
      });
      assertEquals(applied.previousVersionHandles, 1);
      assertEquals(applied.rotatedHandles, 1);
      const rotated = await handleRow(sql, accountId);
      assertEquals(Number(rotated.key_version), activeKey.keyVersion);
      assertEquals(rotated.status, "Active");
      assertEquals(rotated.ciphertext_b64 === before.ciphertext_b64, false);
      assertEquals(rotated.nonce_b64 === before.nonce_b64, false);

      const rerun = await rotateProviderIdentityHandleKeys({
        databaseUrl,
        activeEncryptionKey: activeKey.secret,
        activeKeyVersion: activeKey.keyVersion,
        previousEncryptionKey: previousKey.secret,
        previousKeyVersion: previousKey.keyVersion,
        mode: "apply",
        maxHandles: 100,
        confirmation: "ROTATE-PROVIDER-HANDLES",
      });
      assertEquals(rerun.activeVersionHandles, 1);
      assertEquals(rerun.previousVersionHandles, 0);
      assertEquals(rerun.rotatedHandles, 0);

      await sql`
        update identity.provider_identity_handles
        set key_version=${activeKey.keyVersion + 1}
        where account_id=${accountId}::uuid
      `;
      const unknownBefore = await handleRow(sql, accountId);
      await assertRejects(
        () =>
          rotateProviderIdentityHandleKeys({
            databaseUrl,
            activeEncryptionKey: activeKey.secret,
            activeKeyVersion: activeKey.keyVersion,
            previousEncryptionKey: previousKey.secret,
            previousKeyVersion: previousKey.keyVersion,
            mode: "apply",
            maxHandles: 100,
            confirmation: "ROTATE-PROVIDER-HANDLES",
          }),
        Error,
        "provider_handle_unavailable",
      );
      assertEquals(await handleRow(sql, accountId), unknownBefore);

      await assertRejects(
        () =>
          rotateProviderIdentityHandleKeys({
            databaseUrl,
            activeEncryptionKey: activeKey.secret,
            activeKeyVersion: activeKey.keyVersion,
            previousEncryptionKey: previousKey.secret,
            previousKeyVersion: previousKey.keyVersion,
            mode: "apply",
            maxHandles: 100,
            confirmation: "WRONG",
          }),
        Error,
        "ROTATE-PROVIDER-HANDLES",
      );
    } finally {
      if (accountId) {
        await sql`
          delete from identity.provider_identity_handles
          where account_id=${accountId}::uuid
        `.catch(() => undefined);
        await sql`
          delete from identity.external_identity_tokens
          where account_id=${accountId}::uuid
        `.catch(() => undefined);
        await sql`
          delete from identity.external_identities
          where account_id=${accountId}::uuid
        `.catch(() => undefined);
        await sql`
          delete from core.account_person_links
          where account_id=${accountId}::uuid
        `.catch(() => undefined);
        await sql`
          delete from ecosystem.app_enrollments
          where account_id=${accountId}::uuid
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

async function accountFor(connection: any, appUserId: string): Promise<string> {
  const rows = await connection`
    select identity.account_id_for_legacy_app_user(${appUserId}::uuid)::text
      as account_id
  `;
  const accountId = rows[0]?.account_id;
  if (typeof accountId !== "string" || accountId.length === 0) {
    throw new Error("Expected Account mapping for provider-handle rotation test.");
  }
  return accountId;
}

async function handleRow(connection: any, accountId: string) {
  const rows = await connection`
    select ciphertext_b64,nonce_b64,key_version,status
    from identity.provider_identity_handles
    where account_id=${accountId}::uuid
      and provider='supabase_auth' and issuer='supabase'
  `;
  return rows[0];
}

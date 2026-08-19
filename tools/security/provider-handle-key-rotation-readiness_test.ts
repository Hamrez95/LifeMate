import { assertEquals } from "jsr:@std/assert@1.0.14";
import postgres from "npm:postgres@3.4.7";
import {
  encryptProviderIdentitySubject,
} from "../../supabase/functions/_shared/provider_identity_handle_crypto.ts";
import {
  assessProviderHandleKeyRotationReadiness,
} from "./provider-handle-key-rotation-readiness.ts";

const databaseUrl = Deno.env.get("TEST_DATABASE_URL");
if (!databaseUrl) {
  throw new Error(
    "TEST_DATABASE_URL is required for provider-handle rotation readiness tests.",
  );
}

Deno.test({
  name:
    "provider-handle readiness rejects vacuous/previous/unknown evidence and turns GREEN only on active-version coverage",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
    const sql = postgres(databaseUrl, { max: 1, prepare: false });
    const previousKey = {
      secret: "provider-handle-readiness-previous-key-32-bytes-minimum",
      keyVersion: 101,
    };
    const activeKey = {
      secret: "provider-handle-readiness-active-key-32-bytes-minimum",
      keyVersion: 102,
    };
    const appUserA = crypto.randomUUID();
    const appUserB = crypto.randomUUID();
    const subjectA = crypto.randomUUID();
    const subjectB = crypto.randomUUID();
    let accountA: string | null = null;
    let accountB: string | null = null;

    try {
      const empty = await assessProviderHandleKeyRotationReadiness({
        databaseUrl,
        activeVersion: activeKey.keyVersion,
        previousVersion: previousKey.keyVersion,
      });
      assertEquals(empty.currentHandles, 0);
      assertEquals(empty.readyForPreviousKeyRemoval, false);

      for (const [id, subject] of [
        [appUserA, subjectA],
        [appUserB, subjectB],
      ]) {
        await sql`
          insert into lifemate.app_users(
            id,auth_subject,status,created_at_utc,updated_at_utc
          ) values(${id}::uuid,${subject},'Active',now(),now())
        `;
      }
      accountA = await accountFor(sql, appUserA);
      accountB = await accountFor(sql, appUserB);
      await insertHandle(sql, accountA, subjectA, previousKey);
      await insertHandle(sql, accountB, subjectB, activeKey);
      await sql`
        update identity.provider_identity_handles
        set key_version=${activeKey.keyVersion + 1}
        where account_id=${accountB}::uuid
      `;

      const blocked = await assessProviderHandleKeyRotationReadiness({
        databaseUrl,
        activeVersion: activeKey.keyVersion,
        previousVersion: previousKey.keyVersion,
      });
      assertEquals(blocked.currentHandles, 2);
      assertEquals(blocked.activeVersionReadyHandles, 0);
      assertEquals(blocked.previousVersionHandles, 1);
      assertEquals(blocked.unknownVersionHandles, 1);
      assertEquals(blocked.invalidEnvelopeHandles, 0);
      assertEquals(blocked.readyForPreviousKeyRemoval, false);

      await replaceHandle(sql, accountA, subjectA, activeKey);
      await replaceHandle(sql, accountB, subjectB, activeKey);
      const ready = await assessProviderHandleKeyRotationReadiness({
        databaseUrl,
        activeVersion: activeKey.keyVersion,
        previousVersion: previousKey.keyVersion,
      });
      assertEquals(ready.currentHandles, 2);
      assertEquals(ready.activeVersionReadyHandles, 2);
      assertEquals(ready.previousVersionHandles, 0);
      assertEquals(ready.unknownVersionHandles, 0);
      assertEquals(ready.invalidEnvelopeHandles, 0);
      assertEquals(ready.readyForPreviousKeyRemoval, true);
    } finally {
      for (const accountId of [accountA, accountB]) {
        if (!accountId) continue;
        await sql`
          delete from identity.provider_identity_handles
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
        delete from lifemate.app_users
        where id in (${appUserA}::uuid,${appUserB}::uuid)
      `.catch(() => undefined);
      await sql`
        delete from core.person_profiles
        where person_id in (${appUserA}::uuid,${appUserB}::uuid)
      `.catch(() => undefined);
      await sql`
        delete from core.persons
        where id in (${appUserA}::uuid,${appUserB}::uuid)
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
    throw new Error("Expected Account mapping for provider-handle readiness test.");
  }
  return accountId;
}

async function insertHandle(
  connection: any,
  accountId: string,
  subject: string,
  key: { secret: string; keyVersion: number },
): Promise<void> {
  const envelope = await encryptProviderIdentitySubject(
    key,
    { accountId, provider: "supabase_auth", issuer: "supabase" },
    subject,
  );
  await connection`
    insert into identity.provider_identity_handles(
      account_id,provider,issuer,ciphertext_b64,nonce_b64,key_version,
      status,created_at_utc,updated_at_utc
    ) values(
      ${accountId}::uuid,'supabase_auth','supabase',
      ${envelope.ciphertextB64},${envelope.nonceB64},
      ${envelope.keyVersion},'Active',now(),now()
    )
  `;
}

async function replaceHandle(
  connection: any,
  accountId: string,
  subject: string,
  key: { secret: string; keyVersion: number },
): Promise<void> {
  const envelope = await encryptProviderIdentitySubject(
    key,
    { accountId, provider: "supabase_auth", issuer: "supabase" },
    subject,
  );
  await connection`
    update identity.provider_identity_handles
    set ciphertext_b64=${envelope.ciphertextB64},
        nonce_b64=${envelope.nonceB64},
        key_version=${envelope.keyVersion},
        updated_at_utc=now()
    where account_id=${accountId}::uuid
      and provider='supabase_auth' and issuer='supabase'
  `;
}

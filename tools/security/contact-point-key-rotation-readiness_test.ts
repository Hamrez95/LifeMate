import { assertEquals } from "jsr:@std/assert@1.0.14";
import postgres from "npm:postgres@3.4.7";
import { createContactPointWriter } from "../../supabase/functions/lifemate-api/contact_points.ts";
import { assessContactPointKeyRotationReadiness } from "./contact-point-key-rotation-readiness.ts";

const databaseUrl = Deno.env.get("TEST_DATABASE_URL");
if (!databaseUrl) {
  throw new Error(
    "TEST_DATABASE_URL is required for ContactPoint key-rotation readiness tests.",
  );
}

Deno.test({
  name:
    "ContactPoint key rotation readiness stays RED for previous, unknown or invalid envelopes and GREEN only when every current contact is active-version ready",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
    const sql = postgres(databaseUrl, { max: 1, prepare: false });
    const appUserA = crypto.randomUUID();
    const appUserB = crypto.randomUUID();
    const hashingSecret = "contact-key-readiness-hash-secret-32-bytes-minimum";
    const previousKey = {
      secret: "contact-key-readiness-previous-key-32-bytes-minimum",
      keyVersion: 71,
    };
    const activeKey = {
      secret: "contact-key-readiness-active-key-32-bytes-minimum",
      keyVersion: 72,
    };
    const contactsA = {
      email: `readiness-a-${crypto.randomUUID()}@example.test`,
      phone: "+989121111111",
    };
    const contactsB = {
      email: `readiness-b-${crypto.randomUUID()}@example.test`,
      phone: "+989122222222",
    };
    let accountA: string | null = null;
    let accountB: string | null = null;

    try {
      for (const id of [appUserA, appUserB]) {
        await sql`
          insert into lifemate.app_users(
            id,auth_subject,status,created_at_utc,updated_at_utc
          ) values(${id}::uuid,${crypto.randomUUID()},'Active',now(),now())
        `;
      }
      accountA = await accountFor(sql, appUserA);
      accountB = await accountFor(sql, appUserB);

      const activeWriter = createContactPointWriter(hashingSecret, {
        enabled: true,
        encryptionKey: activeKey,
      });
      const previousWriter = createContactPointWriter(hashingSecret, {
        enabled: true,
        encryptionKey: previousKey,
      });

      await sql.begin(async (tx) => {
        await activeWriter.syncForAccount(
          tx,
          accountA!,
          { email: contactsA.email },
          "replace",
        );
        await previousWriter.syncForAccount(
          tx,
          accountA!,
          { phone: contactsA.phone },
          "replace",
        );
        await activeWriter.syncForAccount(
          tx,
          accountB!,
          { email: contactsB.email, phone: contactsB.phone },
          "replace",
        );
      });

      await sql`
        update identity.contact_points
        set encryption_key_version=${activeKey.keyVersion + 1}
        where account_id=${accountB}::uuid
          and kind='Email' and status <> 'Revoked'
      `;
      await sql`
        update identity.contact_points
        set encrypted_value=null
        where account_id=${accountB}::uuid
          and kind='Phone' and status <> 'Revoked'
      `;

      const blocked = await assessContactPointKeyRotationReadiness({
        databaseUrl,
        activeVersion: activeKey.keyVersion,
        previousVersion: previousKey.keyVersion,
      });
      assertEquals(blocked.currentContacts, 4);
      assertEquals(blocked.activeVersionReadyContacts, 1);
      assertEquals(blocked.previousVersionContacts, 1);
      assertEquals(blocked.unknownVersionContacts, 1);
      assertEquals(blocked.invalidEnvelopeContacts, 1);
      assertEquals(blocked.readyForPreviousKeyRemoval, false);

      await sql.begin(async (tx) => {
        await activeWriter.syncForAccount(
          tx,
          accountA!,
          { email: contactsA.email, phone: contactsA.phone },
          "replace",
        );
        await activeWriter.syncForAccount(
          tx,
          accountB!,
          { email: contactsB.email, phone: contactsB.phone },
          "replace",
        );
      });

      const ready = await assessContactPointKeyRotationReadiness({
        databaseUrl,
        activeVersion: activeKey.keyVersion,
        previousVersion: previousKey.keyVersion,
      });
      assertEquals(ready.currentContacts, 4);
      assertEquals(ready.activeVersionReadyContacts, 4);
      assertEquals(ready.previousVersionContacts, 0);
      assertEquals(ready.unknownVersionContacts, 0);
      assertEquals(ready.invalidEnvelopeContacts, 0);
      assertEquals(ready.readyForPreviousKeyRemoval, true);
    } finally {
      for (const accountId of [accountA, accountB]) {
        if (!accountId) continue;
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
        delete from lifemate.app_users where id in (${appUserA}::uuid,${appUserB}::uuid)
      `.catch(() => undefined);
      await sql`
        delete from core.person_profiles where person_id in (${appUserA}::uuid,${appUserB}::uuid)
      `.catch(() => undefined);
      await sql`
        delete from core.persons where id in (${appUserA}::uuid,${appUserB}::uuid)
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
    throw new Error("Expected Account mapping for ContactPoint readiness test.");
  }
  return accountId;
}

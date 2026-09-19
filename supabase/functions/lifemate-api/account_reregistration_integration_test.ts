import { assert, assertEquals } from "jsr:@std/assert@1.0.14";
import postgres from "postgres";
import { type AuthUser, createLifeMateDatabase } from "./database.ts";
import { closeLifeMateSqlClientsForTest } from "./database_client.ts";
import { createIdentityBridge } from "./identity_bridge.ts";
import { ApiError } from "./validation.ts";

const databaseUrl = Deno.env.get("TEST_DATABASE_URL");
if (!databaseUrl) {
  throw new Error(
    "TEST_DATABASE_URL is required for account re-registration integration tests.",
  );
}

const identityKey = "account-reregistration-test-key-32-bytes-minimum";
const identityKeyVersion = 19;

Deno.test({
  name:
    "completed account deletion permits fresh phone/email registration without reviving the deleted identity",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
    const previousEnvironment = new Map<string, string | undefined>();
    const environmentNames = [
      "LIFEMATE_IDENTITY_LINK_LOOKUP_MODE",
      "LIFEMATE_IDENTITY_LINK_DUAL_WRITE",
      "LIFEMATE_IDENTITY_LINK_KEY",
      "LIFEMATE_IDENTITY_LINK_KEY_VERSION",
      "LIFEMATE_IDENTITY_CONTACT_RAW_RETIREMENT",
    ];
    for (const name of environmentNames) {
      previousEnvironment.set(name, Deno.env.get(name));
    }

    try {
      Deno.env.set("LIFEMATE_IDENTITY_LINK_LOOKUP_MODE", "token-only");
      Deno.env.set("LIFEMATE_IDENTITY_LINK_DUAL_WRITE", "true");
      Deno.env.set("LIFEMATE_IDENTITY_LINK_KEY", identityKey);
      Deno.env.set(
        "LIFEMATE_IDENTITY_LINK_KEY_VERSION",
        String(identityKeyVersion),
      );
      Deno.env.set("LIFEMATE_IDENTITY_CONTACT_RAW_RETIREMENT", "false");

      for (const authKind of ["phone", "email"] as const) {
        await proveFreshRegistration(authKind);
        await closeLifeMateSqlClientsForTest().catch(() => undefined);
      }
    } finally {
      await closeLifeMateSqlClientsForTest().catch(() => undefined);
      for (const [name, value] of previousEnvironment) {
        if (value == null) Deno.env.delete(name);
        else Deno.env.set(name, value);
      }
    }
  },
});

async function proveFreshRegistration(authKind: "phone" | "email") {
  const admin = postgres(databaseUrl!, {
    max: 1,
    prepare: false,
    idle_timeout: 5,
    connect_timeout: 5,
  });
  const authSubject = crypto.randomUUID();
  const auth: AuthUser = {
    id: authSubject,
    email: authKind === "email"
      ? `reregister-${authSubject}@example.test`
      : null,
    phone: authKind === "phone" ? "+12025550123" : null,
    userMetadata: {},
  };
  const db = createLifeMateDatabase(
    databaseUrl!,
    "account-reregistration-contact-secret-32-bytes",
  );
  const bridge = createIdentityBridge(databaseUrl!);

  try {
    const legalAcceptances = await currentLegalAcceptances(db, auth);

    await db.bootstrapUser(auth, {
      displayName: `Original ${authKind}`,
      locale: "en",
      timeZone: "UTC",
      legalAcceptances,
    });

    const originalUsers = await admin`
      select id::text as id
      from lifemate.app_users
      where auth_subject=${authSubject} and status='Active'
    `;
    assertEquals(originalUsers.length, 1);
    const originalAppUserId = String(originalUsers[0].id);

    const originalAccounts = await admin`
      select id::text as id
      from identity.accounts
      where legacy_app_user_id=${originalAppUserId}::uuid
         or (legacy_app_user_id is null and id=${originalAppUserId}::uuid)
      order by case when legacy_app_user_id=${originalAppUserId}::uuid then 0 else 1 end,
               updated_at_utc desc
      limit 1
    `;
    assertEquals(originalAccounts.length, 1);
    const originalAccountId = String(originalAccounts[0].id);

    await bridge.syncExternalIdentities(originalAppUserId, {
      id: authSubject,
      identities: [],
    });

    const originalTokens = await admin`
      select count(*)::int as count
      from identity.external_identity_tokens
      where account_id=${originalAccountId}::uuid
        and provider='supabase_auth'
        and issuer='supabase'
        and status='Active'
    `;
    assertEquals(Number(originalTokens[0].count), 1);

    const deletionRows = await admin`
      select identity.request_account_deletion(${originalAccountId}::uuid)::text as id
    `;
    const deletionRequestId = String(deletionRows[0].id);

    await expectApiError(
      () =>
        db.bootstrapUser(auth, {
          displayName: "must not reactivate pending deletion",
          locale: "en",
          timeZone: "UTC",
          legalAcceptances,
        }),
      409,
      "account_deletion_pending",
    );

    const pendingProof = await admin`
      select a.status as account_status,u.status as app_user_status
      from identity.accounts a
      join lifemate.app_users u on u.id=${originalAppUserId}::uuid
      where a.id=${originalAccountId}::uuid
    `;
    assertEquals(pendingProof[0].account_status, "DeletionPending");
    assertEquals(pendingProof[0].app_user_status, "Disabled");

    const finalized = await admin`
      select identity.finalize_account_deletion(${deletionRequestId}::uuid) as ok
    `;
    assertEquals(finalized[0].ok, true);

    const completedProof = await admin`
      select
        a.status as account_status,
        u.status as app_user_status,
        u.auth_subject,
        p.display_name,
        r.status as deletion_status,
        (select count(*)::int
           from identity.external_identity_tokens t
          where t.account_id=a.id) as token_count,
        (select count(*)::int
           from security.access_grants g
          where g.grantee_account_id=a.id and g.status='Active') as active_grants,
        (select count(*)::int
           from commerce.entitlements e
          where e.grantee_account_id=a.id and e.status='Active') as active_entitlements,
        (select count(*)::int
           from core.account_person_links l
          where l.account_id=a.id and l.status='Active') as active_self_links
      from identity.accounts a
      join lifemate.app_users u on u.id=${originalAppUserId}::uuid
      join lifemate.user_profiles p on p.user_id=u.id
      join identity.account_deletion_requests r on r.account_id=a.id
      where a.id=${originalAccountId}::uuid
      order by r.requested_at_utc desc
      limit 1
    `;
    assertEquals(completedProof[0].account_status, "Deleted");
    assertEquals(completedProof[0].app_user_status, "Deleted");
    assert(String(completedProof[0].auth_subject).startsWith("deleted:"));
    assertEquals(completedProof[0].display_name, "Deleted user");
    assertEquals(completedProof[0].deletion_status, "Completed");
    assertEquals(Number(completedProof[0].token_count), 0);
    assertEquals(Number(completedProof[0].active_grants), 0);
    assertEquals(Number(completedProof[0].active_entitlements), 0);
    assertEquals(Number(completedProof[0].active_self_links), 0);

    const fresh = await db.bootstrapUser(auth, {
      displayName: `Fresh ${authKind}`,
      locale: "en",
      timeZone: "UTC",
      legalAcceptances,
    });

    const freshUsers = await admin`
      select u.id::text as id,p.display_name
      from lifemate.app_users u
      join lifemate.user_profiles p on p.user_id=u.id
      where u.auth_subject=${authSubject} and u.status='Active'
    `;
    assertEquals(freshUsers.length, 1);
    const freshAppUserId = String(freshUsers[0].id);
    assert(freshAppUserId !== originalAppUserId);
    assertEquals(freshUsers[0].display_name, `Fresh ${authKind}`);

    const freshProfile = fresh.profile as Record<string, unknown> | undefined;
    if (freshProfile) {
      assertEquals(freshProfile.displayName, `Fresh ${authKind}`);
    }

    const freshAccounts = await admin`
      select a.id::text as id,l.person_id::text as person_id
      from identity.accounts a
      join core.account_person_links l
        on l.account_id=a.id and l.link_type='Self' and l.status='Active'
      where a.legacy_app_user_id=${freshAppUserId}::uuid
         or (a.legacy_app_user_id is null and a.id=${freshAppUserId}::uuid)
      order by case when a.legacy_app_user_id=${freshAppUserId}::uuid then 0 else 1 end,
               a.updated_at_utc desc
      limit 1
    `;
    assertEquals(freshAccounts.length, 1);
    const freshAccountId = String(freshAccounts[0].id);
    assert(freshAccountId !== originalAccountId);

    await bridge.syncExternalIdentities(freshAppUserId, {
      id: authSubject,
      identities: [],
    });

    const freshTokenProof = await admin`
      select count(*)::int as count
      from identity.external_identity_tokens
      where account_id=${freshAccountId}::uuid
        and provider='supabase_auth'
        and issuer='supabase'
        and status='Active'
    `;
    assertEquals(Number(freshTokenProof[0].count), 1);

    const repeated = await db.bootstrapUser(auth, {
      displayName: "must keep fresh profile",
      locale: "fa",
      timeZone: "Asia/Tehran",
      legalAcceptances,
    });
    const repeatedProfile = repeated.profile as Record<string, unknown>;
    assertEquals(repeatedProfile.displayName, `Fresh ${authKind}`);

    const finalIsolation = await admin`
      select
        (select count(*)::int
           from lifemate.app_users
          where auth_subject=${authSubject} and status='Active') as active_users,
        (select count(*)::int
           from identity.external_identity_tokens
          where account_id=${originalAccountId}::uuid) as old_tokens,
        (select count(*)::int
           from core.account_person_links
          where account_id=${originalAccountId}::uuid and status='Active') as old_links,
        (select count(*)::int
           from commerce.entitlements
          where grantee_account_id=${originalAccountId}::uuid and status='Active') as old_entitlements
    `;
    assertEquals(Number(finalIsolation[0].active_users), 1);
    assertEquals(Number(finalIsolation[0].old_tokens), 0);
    assertEquals(Number(finalIsolation[0].old_links), 0);
    assertEquals(Number(finalIsolation[0].old_entitlements), 0);
  } finally {
    await admin.end({ timeout: 5 }).catch(() => undefined);
  }
}

async function currentLegalAcceptances(
  db: ReturnType<typeof createLifeMateDatabase>,
  auth: AuthUser,
): Promise<{ documentId: string; documentHash: string }[]> {
  const preflight = await db.bootstrapUser(auth, {
    registrationPreflight: true,
  });
  const registration = preflight.registration as
    | Record<string, unknown>
    | undefined;
  const documents = registration?.requiredDocuments;
  assert(Array.isArray(documents));
  return documents.map((value) => {
    assert(value && typeof value === "object" && !Array.isArray(value));
    const document = value as Record<string, unknown>;
    assert(typeof document.id === "string");
    assert(typeof document.documentHash === "string");
    return {
      documentId: document.id,
      documentHash: document.documentHash,
    };
  });
}

async function expectApiError(
  action: () => Promise<unknown>,
  status: number,
  code: string,
): Promise<void> {
  try {
    await action();
  } catch (error) {
    if (error instanceof ApiError) {
      assertEquals(error.status, status);
      assertEquals(error.code, code);
      return;
    }
    throw error;
  }
  throw new Error(`Expected ApiError ${status}/${code}.`);
}

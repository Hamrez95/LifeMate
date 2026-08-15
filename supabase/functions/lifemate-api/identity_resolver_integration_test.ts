import { assertEquals } from "jsr:@std/assert@1.0.14";
import postgres from "postgres";
import { deriveIdentityLinkToken } from "./identity_link_token.ts";
import { createIdentityResolver } from "./identity_resolver.ts";
import { ApiError } from "./validation.ts";

const databaseUrl = Deno.env.get("TEST_DATABASE_URL");
if (!databaseUrl) {
  throw new Error(
    "TEST_DATABASE_URL is required for identity resolver integration tests.",
  );
}

const sql = postgres(databaseUrl, {
  max: 1,
  prepare: false,
  idle_timeout: 5,
  connect_timeout: 5,
});

Deno.test({
  name: "token lookup resolves canonical Account to remapped AppUser and fails closed",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
    const appUserA = crypto.randomUUID();
    const appUserB = crypto.randomUUID();
    const remappedAccountA = crypto.randomUUID();
    const authSubject = crypto.randomUUID();
    const originalAuthSubjectA = `retired-${crypto.randomUUID()}`;
    const authSubjectB = authSubject;
    const key = "abcdef0123456789abcdef0123456789";
    const keyVersion = 7;

    const auth = {
      id: authSubject,
      email: null,
      phone: null,
      userMetadata: {},
    };

    try {
      await sql`
        insert into lifemate.app_users(
          id,auth_subject,status,created_at_utc,updated_at_utc
        ) values(
          ${appUserA}::uuid,${originalAuthSubjectA},'Active',now(),now()
        )
      `;
      await sql`
        update identity.accounts
        set legacy_app_user_id=null,updated_at_utc=now()
        where id=${appUserA}::uuid
      `;
      await sql`
        insert into identity.accounts(
          id,legacy_app_user_id,status,created_at_utc,updated_at_utc
        ) values(
          ${remappedAccountA}::uuid,${appUserA}::uuid,'Active',now(),now()
        )
      `;
      await sql`
        insert into lifemate.app_users(
          id,auth_subject,status,created_at_utc,updated_at_utc
        ) values(
          ${appUserB}::uuid,${authSubjectB},'Active',now(),now()
        )
      `;

      const token = await deriveIdentityLinkToken(key, {
        provider: "supabase_auth",
        issuer: "supabase",
        subject: authSubject,
        keyVersion,
      });
      await sql`
        insert into identity.external_identity_tokens(
          account_id,provider,issuer,subject_token,key_version,status,
          created_at_utc,last_authenticated_at_utc
        ) values(
          ${remappedAccountA}::uuid,'supabase_auth','supabase',${token},
          ${keyVersion},'Active',now(),now()
        )
      `;

      const tokenOnly = createIdentityResolver(databaseUrl, {
        mode: "token-only",
        dualWriteEnabled: true,
        identityLinkKey: { secret: key, keyVersion },
      });
      const tokenOnlyIdentity = await tokenOnly.requireIdentity(auth);
      assertEquals(tokenOnlyIdentity.appUserId, appUserA);

      const preferToken = createIdentityResolver(databaseUrl, {
        mode: "prefer-token",
        dualWriteEnabled: true,
        identityLinkKey: { secret: key, keyVersion },
      });
      const preferredIdentity = await preferToken.requireIdentity(auth);
      assertEquals(
        preferredIdentity.appUserId,
        appUserA,
        "token mapping must win over a conflicting legacy raw-subject lookup",
      );

      await sql`
        delete from identity.external_identity_tokens
        where account_id=${remappedAccountA}::uuid
          and provider='supabase_auth'
          and issuer='supabase'
          and key_version=${keyVersion}
      `;
      const fallbackIdentity = await preferToken.requireIdentity(auth);
      assertEquals(fallbackIdentity.appUserId, appUserB);
      await assertApiError(
        () => tokenOnly.requireIdentity(auth),
        404,
        "not_onboarded",
      );

      await sql`
        insert into identity.external_identity_tokens(
          account_id,provider,issuer,subject_token,key_version,status,
          created_at_utc,last_authenticated_at_utc
        ) values(
          ${remappedAccountA}::uuid,'supabase_auth','supabase',${token},
          ${keyVersion},'Active',now(),now()
        )
      `;
      await sql`
        update identity.accounts
        set legacy_app_user_id=null,updated_at_utc=now()
        where id=${remappedAccountA}::uuid
      `;
      await assertApiError(
        () => preferToken.requireIdentity(auth),
        409,
        "identity_account_mapping_missing",
      );
    } finally {
      await sql`
        delete from identity.external_identity_tokens
        where account_id in (
          ${appUserA}::uuid,${appUserB}::uuid,${remappedAccountA}::uuid
        )
      `.catch(() => undefined);
      await sql`
        delete from identity.external_identities
        where account_id in (
          ${appUserA}::uuid,${appUserB}::uuid,${remappedAccountA}::uuid
        )
      `.catch(() => undefined);
      await sql`
        update identity.accounts
        set legacy_app_user_id=null,updated_at_utc=now()
        where id in (${appUserA}::uuid,${appUserB}::uuid,${remappedAccountA}::uuid)
      `.catch(() => undefined);
      await sql`
        delete from identity.accounts
        where id in (${appUserA}::uuid,${appUserB}::uuid,${remappedAccountA}::uuid)
      `.catch(() => undefined);
      await sql`
        delete from lifemate.app_users
        where id in (${appUserA}::uuid,${appUserB}::uuid)
      `.catch(() => undefined);
      await sql`
        delete from core.persons
        where id in (${appUserA}::uuid,${appUserB}::uuid)
      `.catch(() => undefined);
    }
  },
});

async function assertApiError(
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

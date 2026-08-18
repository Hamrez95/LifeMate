import { assertEquals } from "jsr:@std/assert@1.0.14";
import postgres from "postgres";
import { deriveIdentityLinkToken } from "./identity_link_token.ts";
import { createIdentityResolver } from "./identity_resolver.ts";
import { ApiError } from "./validation.ts";

const databaseUrl = Deno.env.get("TEST_DATABASE_URL");
if (!databaseUrl) {
  throw new Error(
    "TEST_DATABASE_URL is required for identity-link rotation integration tests.",
  );
}

Deno.test({
  name:
    "token-only key rotation resolves previous token, lazily adds active token and fails closed on cross-key conflict",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
    const sql = postgres(databaseUrl, {
      max: 1,
      prepare: false,
      idle_timeout: 5,
      connect_timeout: 5,
    });
    const appUserA = crypto.randomUUID();
    const appUserB = crypto.randomUUID();
    const rawOnlyAppUser = crypto.randomUUID();
    const remappedAccountA = crypto.randomUUID();
    const authSubject = crypto.randomUUID();
    const rawOnlySubject = crypto.randomUUID();
    const activeKey = {
      secret: "identity-link-rotation-active-key-32-bytes-minimum",
      keyVersion: 8,
    };
    const previousKey = {
      secret: "identity-link-rotation-previous-key-32-bytes-minimum",
      keyVersion: 7,
    };
    const auth = {
      id: authSubject,
      email: null,
      phone: null,
      userMetadata: {},
    };
    const rawOnlyAuth = {
      id: rawOnlySubject,
      email: null,
      phone: null,
      userMetadata: {},
    };

    try {
      // Build an explicit Account != AppUser mapping for A. AppUser B retains
      // the target raw subject on purpose, proving token-only rotation never
      // falls through to that contradictory legacy mapping.
      await sql`
        insert into lifemate.app_users(
          id,auth_subject,status,created_at_utc,updated_at_utc
        ) values(
          ${appUserA}::uuid,${`legacy-a-${crypto.randomUUID()}`},
          'Active',now(),now()
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
          ${appUserB}::uuid,${authSubject},'Active',now(),now()
        )
      `;
      await sql`
        insert into lifemate.app_users(
          id,auth_subject,status,created_at_utc,updated_at_utc
        ) values(
          ${rawOnlyAppUser}::uuid,${rawOnlySubject},'Active',now(),now()
        )
      `;

      const previousToken = await deriveIdentityLinkToken(previousKey.secret, {
        provider: "supabase_auth",
        issuer: "supabase",
        subject: authSubject,
        keyVersion: previousKey.keyVersion,
      });
      const activeToken = await deriveIdentityLinkToken(activeKey.secret, {
        provider: "supabase_auth",
        issuer: "supabase",
        subject: authSubject,
        keyVersion: activeKey.keyVersion,
      });
      await sql`
        insert into identity.external_identity_tokens(
          account_id,provider,issuer,subject_token,key_version,status,
          created_at_utc,last_authenticated_at_utc
        ) values(
          ${remappedAccountA}::uuid,'supabase_auth','supabase',${previousToken},
          ${previousKey.keyVersion},'Active',now(),now()
        )
      `;

      const resolver = createIdentityResolver(databaseUrl, {
        mode: "token-only",
        dualWriteEnabled: true,
        identityLinkKey: activeKey,
        previousIdentityLinkKey: previousKey,
      });

      // A current-version token owned by a different Account must not be hidden
      // by a valid previous token. The overlap is ambiguous and fails closed.
      await sql`
        insert into identity.external_identity_tokens(
          account_id,provider,issuer,subject_token,key_version,status,
          created_at_utc,last_authenticated_at_utc
        ) values(
          ${appUserB}::uuid,'supabase_auth','supabase',${activeToken},
          ${activeKey.keyVersion},'Active',now(),now()
        )
      `;
      await assertApiError(
        () => resolver.requireIdentity(auth),
        409,
        "identity_token_rotation_conflict",
      );
      await sql`
        delete from identity.external_identity_tokens
        where account_id=${appUserB}::uuid
          and provider='supabase_auth'
          and issuer='supabase'
          and key_version=${activeKey.keyVersion}
      `;

      // Previous-only resolution returns the explicitly remapped AppUser and
      // atomically creates the active-version token for that same Account.
      const rotated = await resolver.requireIdentity(auth);
      assertEquals(rotated.appUserId, appUserA);
      const tokenRows = await sql`
        select account_id::text as account_id,key_version
        from identity.external_identity_tokens
        where provider='supabase_auth'
          and issuer='supabase'
          and account_id=${remappedAccountA}::uuid
          and status='Active'
        order by key_version
      `;
      assertEquals(tokenRows.length, 2);
      assertEquals(tokenRows[0]?.key_version, previousKey.keyVersion);
      assertEquals(tokenRows[1]?.key_version, activeKey.keyVersion);
      assertEquals(tokenRows[0]?.account_id, remappedAccountA);
      assertEquals(tokenRows[1]?.account_id, remappedAccountA);

      // Once the active token exists, repeated lookup remains stable. The raw B
      // mapping for the same subject is never consulted in token-only mode.
      const repeated = await resolver.requireIdentity(auth);
      assertEquals(repeated.appUserId, appUserA);

      // A raw-only legacy mapping is not enough once token-only is authoritative.
      await assertApiError(
        () => resolver.requireIdentity(rawOnlyAuth),
        404,
        "not_onboarded",
      );
    } finally {
      await sql`
        delete from identity.external_identity_tokens
        where account_id in (
          ${appUserA}::uuid,${appUserB}::uuid,${rawOnlyAppUser}::uuid,
          ${remappedAccountA}::uuid
        )
      `.catch(() => undefined);
      await sql`
        delete from identity.external_identities
        where account_id in (
          ${appUserA}::uuid,${appUserB}::uuid,${rawOnlyAppUser}::uuid,
          ${remappedAccountA}::uuid
        )
      `.catch(() => undefined);
      await sql`
        delete from core.account_person_links
        where account_id=${remappedAccountA}::uuid
      `.catch(() => undefined);
      await sql`
        update identity.accounts
        set legacy_app_user_id=null,updated_at_utc=now()
        where id in (
          ${appUserA}::uuid,${appUserB}::uuid,${rawOnlyAppUser}::uuid,
          ${remappedAccountA}::uuid
        )
      `.catch(() => undefined);
      await sql`
        delete from identity.accounts
        where id in (
          ${appUserA}::uuid,${appUserB}::uuid,${rawOnlyAppUser}::uuid,
          ${remappedAccountA}::uuid
        )
      `.catch(() => undefined);
      await sql`
        delete from lifemate.app_users
        where id in (
          ${appUserA}::uuid,${appUserB}::uuid,${rawOnlyAppUser}::uuid
        )
      `.catch(() => undefined);
      await sql`
        delete from core.person_profiles
        where person_id in (
          ${appUserA}::uuid,${appUserB}::uuid,${rawOnlyAppUser}::uuid
        )
      `.catch(() => undefined);
      await sql`
        delete from core.persons
        where id in (
          ${appUserA}::uuid,${appUserB}::uuid,${rawOnlyAppUser}::uuid
        )
      `.catch(() => undefined);
      await sql.end({ timeout: 5 });
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

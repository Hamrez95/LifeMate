import { assertEquals } from "jsr:@std/assert@1.0.14";
import postgres from "postgres";
import { closeLifeMateSqlClientsForTest } from "./database_client.ts";
import { createPregnancyAuthorization } from "./pregnancy_authorization.ts";

const databaseUrl = Deno.env.get("TEST_DATABASE_URL");
if (!databaseUrl) {
  throw new Error(
    "TEST_DATABASE_URL is required for pregnancy authorization tests.",
  );
}

const sql = postgres(databaseUrl, {
  max: 1,
  prepare: false,
  idle_timeout: 5,
  connect_timeout: 5,
});

type Authorization = ReturnType<typeof createPregnancyAuthorization>;
type AccessArgs = Parameters<Authorization["hasAccess"]>[0];

async function assertAccess(
  authorization: Authorization,
  args: AccessArgs,
  expected: boolean,
): Promise<void> {
  assertEquals(await authorization.hasAccess(args), expected);
}

Deno.test({
  name:
    "pregnancy authorization requires exact grant and explicit episode consent",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
    const ownerAccountId = crypto.randomUUID();
    const ownerPersonId = crypto.randomUUID();
    const partnerAccountId = crypto.randomUUID();
    const partnerPersonId = crypto.randomUUID();
    const unrelatedAccountId = crypto.randomUUID();
    const unrelatedPersonId = crypto.randomUUID();
    const episodeId = crypto.randomUUID();
    const relationshipId = crypto.randomUUID();
    const grantId = crypto.randomUUID();
    const consentDocumentId = crypto.randomUUID();
    const consentRecordId = crypto.randomUUID();
    const consentVersion = `pregnancy-auth-${crypto.randomUUID()}`;
    const idempotencyHash = crypto.randomUUID().replaceAll("-", "").repeat(2);
    const authorization = createPregnancyAuthorization(databaseUrl);

    try {
      const functionDefinitionRows = await sql`
        select pg_get_functiondef(
          'security.can_access_pregnancy_scope(uuid,uuid,uuid,character varying,timestamp with time zone)'::regprocedure
        ) as definition
      `;
      const functionDefinition = String(
        functionDefinitionRows[0]?.definition ?? "",
      ).toLowerCase();
      assertEquals(functionDefinition.includes("commerce."), false);
      assertEquals(functionDefinition.includes("network."), false);

      await sql`
        insert into identity.accounts(id,status) values
          (${ownerAccountId}::uuid,'Active'),
          (${partnerAccountId}::uuid,'Active'),
          (${unrelatedAccountId}::uuid,'Active')
      `;
      await sql`
        insert into core.persons(id,status,subject_category) values
          (${ownerPersonId}::uuid,'Active','Adult'),
          (${partnerPersonId}::uuid,'Active','Adult'),
          (${unrelatedPersonId}::uuid,'Active','Adult')
      `;
      await sql`
        insert into core.account_person_links(
          account_id,person_id,link_type,status
        ) values
          (${ownerAccountId}::uuid,${ownerPersonId}::uuid,'Self','Active'),
          (${partnerAccountId}::uuid,${partnerPersonId}::uuid,'Self','Active'),
          (${unrelatedAccountId}::uuid,${unrelatedPersonId}::uuid,'Self','Active')
      `;
      await sql`
        insert into pregnancy.episodes(
          id,mother_person_id,status,activated_at_utc,
          creation_idempotency_key_hash
        ) values (
          ${episodeId}::uuid,${ownerPersonId}::uuid,'active',now(),
          ${idempotencyHash}
        )
      `;

      // The owner's active Self link is sufficient for owner access.
      await assertAccess(authorization, {
        callerAccountId: ownerAccountId,
        subjectPersonId: ownerPersonId,
        episodeId,
        scope: "pregnancy.summary.read",
      }, true);
      await assertAccess(authorization, {
        callerAccountId: ownerAccountId,
        subjectPersonId: ownerPersonId,
        episodeId,
        scope: "pregnancy.owner.manage",
      }, true);

      // Knowing canonical UUIDs is never authorization.
      await assertAccess(authorization, {
        callerAccountId: unrelatedAccountId,
        subjectPersonId: ownerPersonId,
        episodeId,
        scope: "pregnancy.summary.read",
      }, false);

      // A natural relationship does not create a health grant or authorize PHI.
      await sql`
        insert into network.person_relationships(
          id,source_person_id,target_person_id,relationship_type,status
        ) values (
          ${relationshipId}::uuid,${partnerPersonId}::uuid,
          ${ownerPersonId}::uuid,'Spouse','Active'
        )
      `;
      await assertAccess(authorization, {
        callerAccountId: partnerAccountId,
        subjectPersonId: ownerPersonId,
        episodeId,
        scope: "pregnancy.summary.read",
      }, false);
      const relationshipGrantCount = await sql`
        select count(*)::int as count
        from security.access_grants
        where subject_person_id=${ownerPersonId}::uuid
          and grantee_account_id=${partnerAccountId}::uuid
      `;
      assertEquals(Number(relationshipGrantCount[0].count), 0);

      // Commerce is structurally absent from the resolver, so entitlement state
      // cannot authorize pregnancy PHI without an explicit health grant/consent.
      await assertAccess(authorization, {
        callerAccountId: partnerAccountId,
        subjectPersonId: ownerPersonId,
        episodeId,
        scope: "pregnancy.summary.read",
      }, false);

      // A grant without contextual consent is still denied.
      await sql`
        insert into security.access_grants(
          id,subject_person_id,grantee_account_id,grantor_person_id,
          context_type,context_id,status,starts_at_utc
        ) values (
          ${grantId}::uuid,${ownerPersonId}::uuid,${partnerAccountId}::uuid,
          ${ownerPersonId}::uuid,'pregnancy_episode',${episodeId}::uuid,
          'Active',now()
        )
      `;
      await sql`
        insert into security.access_grant_scopes(grant_id,scope)
        values (${grantId}::uuid,'pregnancy.summary.read')
      `;
      await assertAccess(authorization, {
        callerAccountId: partnerAccountId,
        subjectPersonId: ownerPersonId,
        episodeId,
        scope: "pregnancy.summary.read",
      }, false);

      await sql`
        insert into consent.consent_documents(
          id,purpose,version,jurisdiction,title,status,effective_at_utc
        ) values (
          ${consentDocumentId}::uuid,'pregnancy_sharing',${consentVersion},
          '*','Pregnancy sharing authorization test','Active',now()
        )
      `;
      await sql`
        insert into consent.consent_records(
          id,subject_person_id,actor_account_id,document_id,purpose,
          scope_key,data_categories,jurisdiction,source,status,granted_at_utc
        ) values (
          ${consentRecordId}::uuid,${ownerPersonId}::uuid,
          ${ownerAccountId}::uuid,${consentDocumentId}::uuid,
          'pregnancy_sharing',${`pregnancy_episode:${episodeId}`},
          array['pregnancy_health'],'*','cocoon_test','Granted',now()
        )
      `;

      await assertAccess(authorization, {
        callerAccountId: partnerAccountId,
        subjectPersonId: ownerPersonId,
        episodeId,
        scope: "pregnancy.summary.read",
      }, true);

      // Scope shaping is exact; summary does not imply observations or owner control.
      await assertAccess(authorization, {
        callerAccountId: partnerAccountId,
        subjectPersonId: ownerPersonId,
        episodeId,
        scope: "pregnancy.observations.read",
      }, false);
      await assertAccess(authorization, {
        callerAccountId: partnerAccountId,
        subjectPersonId: ownerPersonId,
        episodeId,
        scope: "pregnancy.owner.manage",
      }, false);

      // Consent revocation takes effect on the next server authorization check.
      await sql`
        update consent.consent_records
        set status='Revoked',revoked_at_utc=now(),updated_at_utc=now()
        where id=${consentRecordId}::uuid
      `;
      await assertAccess(authorization, {
        callerAccountId: partnerAccountId,
        subjectPersonId: ownerPersonId,
        episodeId,
        scope: "pregnancy.summary.read",
      }, false);
      await sql`
        update consent.consent_records
        set status='Granted',revoked_at_utc=null,granted_at_utc=now(),
            updated_at_utc=now()
        where id=${consentRecordId}::uuid
      `;

      // Grant revocation and expiry also fail closed immediately.
      await sql`
        update security.access_grants
        set status='Revoked',revoked_at_utc=now(),updated_at_utc=now()
        where id=${grantId}::uuid
      `;
      await assertAccess(authorization, {
        callerAccountId: partnerAccountId,
        subjectPersonId: ownerPersonId,
        episodeId,
        scope: "pregnancy.summary.read",
      }, false);
      await sql`
        update security.access_grants
        set status='Active',revoked_at_utc=null,
            expires_at_utc=now()-interval '1 second',
            updated_at_utc=now()
        where id=${grantId}::uuid
      `;
      await assertAccess(authorization, {
        callerAccountId: partnerAccountId,
        subjectPersonId: ownerPersonId,
        episodeId,
        scope: "pregnancy.summary.read",
      }, false);

      // Shared access does not silently persist into ended pregnancy history.
      await sql`
        update security.access_grants
        set expires_at_utc=null,updated_at_utc=now()
        where id=${grantId}::uuid
      `;
      await sql`
        update pregnancy.episodes
        set status='ended',outcome='other',ended_at_utc=now()
        where id=${episodeId}::uuid
      `;
      await assertAccess(authorization, {
        callerAccountId: partnerAccountId,
        subjectPersonId: ownerPersonId,
        episodeId,
        scope: "pregnancy.summary.read",
      }, false);
      await assertAccess(authorization, {
        callerAccountId: ownerAccountId,
        subjectPersonId: ownerPersonId,
        episodeId,
        scope: "pregnancy.summary.read",
      }, true);
    } finally {
      await closeLifeMateSqlClientsForTest().catch(() => undefined);
      await sql`
        delete from consent.consent_records where id=${consentRecordId}::uuid
      `.catch(() => undefined);
      await sql`
        delete from consent.consent_documents where id=${consentDocumentId}::uuid
      `.catch(() => undefined);
      await sql`
        delete from security.access_grants where id=${grantId}::uuid
      `.catch(() => undefined);
      await sql`
        delete from network.person_relationships where id=${relationshipId}::uuid
      `.catch(() => undefined);
      await sql`
        delete from pregnancy.episodes where id=${episodeId}::uuid
      `.catch(() => undefined);
      await sql`
        delete from core.account_person_links where account_id in (
          ${ownerAccountId}::uuid,${partnerAccountId}::uuid,${unrelatedAccountId}::uuid
        )
      `.catch(() => undefined);
      await sql`
        delete from core.persons where id in (
          ${ownerPersonId}::uuid,${partnerPersonId}::uuid,${unrelatedPersonId}::uuid
        )
      `.catch(() => undefined);
      await sql`
        delete from identity.accounts where id in (
          ${ownerAccountId}::uuid,${partnerAccountId}::uuid,${unrelatedAccountId}::uuid
        )
      `.catch(() => undefined);
      await sql.end({ timeout: 1 }).catch(() => undefined);
    }
  },
});

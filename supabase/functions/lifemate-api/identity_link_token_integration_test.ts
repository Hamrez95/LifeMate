import { assertEquals, assertRejects } from "jsr:@std/assert@1.0.14";
import postgres from "postgres";

const databaseUrl = Deno.env.get("TEST_DATABASE_URL");
if (!databaseUrl) {
  throw new Error(
    "TEST_DATABASE_URL is required for identity-link integration tests.",
  );
}

const sql = postgres(databaseUrl, {
  max: 1,
  prepare: false,
  idle_timeout: 5,
  connect_timeout: 5,
});

Deno.test({
  name: "external identity token storage cannot persist raw provider subjects",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
    const accountA = crypto.randomUUID();
    const accountB = crypto.randomUUID();
    const token = "a".repeat(64);

    try {
      const rawSubjectColumns = await sql`
        select column_name
        from information_schema.columns
        where table_schema='identity'
          and table_name='external_identity_tokens'
          and column_name in ('provider_subject','auth_subject','email','phone')
      `;
      assertEquals(rawSubjectColumns.length, 0);

      await sql`
        insert into identity.accounts(id,status)
        values (${accountA}::uuid,'Active'),(${accountB}::uuid,'Active')
      `;
      await sql`
        insert into identity.external_identity_tokens(
          account_id,provider,issuer,subject_token,key_version,status
        ) values(
          ${accountA}::uuid,'supabase_auth','supabase',${token},1,'Active'
        )
      `;

      const stored = await sql`
        select account_id,provider,issuer,subject_token,key_version,status
        from identity.external_identity_tokens
        where account_id=${accountA}::uuid
      `;
      assertEquals(String(stored[0].account_id), accountA);
      assertEquals(stored[0].provider, "supabase_auth");
      assertEquals(stored[0].issuer, "supabase");
      assertEquals(stored[0].subject_token, token);
      assertEquals(Number(stored[0].key_version), 1);
      assertEquals(stored[0].status, "Active");

      await assertRejects(
        () =>
          sql`
          insert into identity.external_identity_tokens(
            account_id,provider,issuer,subject_token,key_version,status
          ) values(
            ${accountB}::uuid,'supabase_auth','supabase',${token},1,'Active'
          )
        `,
        Error,
      );

      await assertRejects(
        () =>
          sql`
          insert into identity.external_identity_tokens(
            account_id,provider,issuer,subject_token,key_version,status
          ) values(
            ${accountB}::uuid,'supabase_auth','supabase','raw-subject',1,'Active'
          )
        `,
        Error,
      );

      await sql`
        update identity.accounts set status='Deleted',updated_at_utc=now()
        where id=${accountA}::uuid
      `;
      const afterDeletion = await sql`
        select count(*)::int as count
        from identity.external_identity_tokens
        where account_id=${accountA}::uuid
      `;
      assertEquals(Number(afterDeletion[0].count), 0);
    } finally {
      await sql`
        delete from identity.external_identity_tokens
        where account_id in (${accountA}::uuid,${accountB}::uuid)
      `.catch(() => undefined);
      await sql`
        delete from identity.accounts
        where id in (${accountA}::uuid,${accountB}::uuid)
      `.catch(() => undefined);
    }
  },
});

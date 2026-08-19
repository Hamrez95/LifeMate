import { assertEquals, assertRejects } from "jsr:@std/assert@1.0.14";
import postgres from "postgres";
import { closeLifeMateSqlClientsForTest } from "./database_client.ts";
import { type AuthUser, createLifeMateDatabase } from "./database.ts";
import { createIdentityBridge } from "./identity_bridge.ts";
import { createPersonDoseOccurrenceStore } from "./person_dose_occurrences.ts";
import { createPersonMedicationStore } from "./person_medications.ts";
import { createPersonTreatmentPlanStore } from "./person_treatment_plans.ts";
import { createWomenCalendarStore } from "./women_calendar.ts";

const databaseUrl = Deno.env.get("TEST_DATABASE_URL");
if (!databaseUrl) {
  throw new Error(
    "TEST_DATABASE_URL is required for database-only breach proof tests.",
  );
}

const envNames = [
  "LIFEMATE_IDENTITY_LINK_LOOKUP_MODE",
  "LIFEMATE_IDENTITY_LINK_DUAL_WRITE",
  "LIFEMATE_IDENTITY_LINK_KEY",
  "LIFEMATE_IDENTITY_LINK_KEY_VERSION",
  "LIFEMATE_IDENTITY_PROVIDER_HANDLE_DUAL_WRITE",
  "LIFEMATE_IDENTITY_PROVIDER_HANDLE_KEY",
  "LIFEMATE_IDENTITY_PROVIDER_HANDLE_KEY_VERSION",
  "LIFEMATE_IDENTITY_LINK_RAW_RETIREMENT",
  "LIFEMATE_PROFILE_CONTACT_LOOKUP_MODE",
  "LIFEMATE_IDENTITY_CONTACT_ENCRYPTION_KEY",
  "LIFEMATE_IDENTITY_CONTACT_ENCRYPTION_KEY_VERSION",
  "LIFEMATE_IDENTITY_CONTACT_READINESS_APPROVED",
  "LIFEMATE_IDENTITY_CONTACT_RAW_RETIREMENT",
  "LIFEMATE_IDENTITY_CONTACT_DUAL_WRITE",
] as const;

Deno.test({
  name:
    "synthetic application-schema dump cannot directly map known login identity to Person healthcare without external keys",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
    const sql = postgres(databaseUrl, {
      max: 1,
      prepare: false,
      idle_timeout: 5,
      connect_timeout: 5,
    });
    const previous = new Map<string, string | undefined>();
    for (const name of envNames) previous.set(name, Deno.env.get(name));

    const authSubject = crypto.randomUUID();
    const providerSubject = `google-${crypto.randomUUID()}`;
    const email = `db-breach-${crypto.randomUUID()}@example.test`;
    const phone = "+989121234567";
    const tokenKey = "synthetic-db-breach-identity-hmac-key-32-bytes-minimum";
    const providerHandleKey =
      "synthetic-db-breach-provider-handle-key-32-bytes-minimum";
    const contactEncryptionKey =
      "synthetic-db-breach-contact-envelope-key-32-bytes-minimum";
    const contactHashSecret =
      "synthetic-db-breach-contact-hash-key-32-bytes-minimum";
    const accountId = crypto.randomUUID();
    const personId = crypto.randomUUID();
    const auth: AuthUser = {
      id: authSubject,
      email,
      phone,
      userMetadata: {},
    };

    try {
      configurePostRetirementIdentity({
        tokenKey,
        providerHandleKey,
        contactEncryptionKey,
      });

      const db = createLifeMateDatabase(databaseUrl, contactHashSecret);
      await db.bootstrapUser(auth, {
        displayName: "Synthetic Breach Fixture",
        locale: "fa",
        timeZone: "Asia/Tehran",
      });
      const bootstrapIdentity = await db.requireIdentity(auth);
      const appUserId = bootstrapIdentity.appUserId;
      const bootstrapAccountRows = await sql`
        select identity.account_id_for_legacy_app_user(${appUserId}::uuid)::text
          as account_id
      `;
      const bootstrapAccountId = String(
        bootstrapAccountRows[0]?.account_id ?? "",
      );
      if (!bootstrapAccountId) {
        throw new Error("Synthetic breach bootstrap Account missing.");
      }

      await remapBootstrapIdentity(sql, {
        appUserId,
        bootstrapAccountId,
        accountId,
        personId,
      });
      assertAllDifferent(authSubject, appUserId, accountId, personId);

      // Token-only resolution must now return the remapped Account/Person state.
      const resolved = await db.requireIdentity(auth);
      assertEquals(resolved.appUserId, appUserId);
      const resolvedAccount = await sql`
        select account_id::text as account_id
        from identity.external_identity_tokens
        where account_id=${accountId}::uuid and status='Active'
        limit 1
      `;
      assertEquals(String(resolvedAccount[0]?.account_id), accountId);

      const bridge = createIdentityBridge(databaseUrl, contactHashSecret);
      assertEquals(
        await bridge.syncExternalIdentities(appUserId, {
          id: authSubject,
          identities: [{
            provider: "google",
            identity_data: { sub: providerSubject },
            created_at: new Date().toISOString(),
            last_sign_in_at: new Date().toISOString(),
          }],
        }),
        ["google"],
      );

      const schedule = futureLocalSchedule();
      const medicationStore = createPersonMedicationStore(databaseUrl);
      const treatmentStore = createPersonTreatmentPlanStore(databaseUrl);
      const doseStore = createPersonDoseOccurrenceStore(databaseUrl);
      const medication = await medicationStore.createMedication(appUserId, {
        name: "Synthetic fixture medicine",
        strengthText: "10 mg",
        form: "tablet",
        notes: null,
      });
      const treatment = await treatmentStore.createTreatmentPlan(appUserId, {
        medicationId: String(medication.id),
        doseText: "1 tablet",
        instructions: null,
        startDate: schedule.date,
        endDate: schedule.date,
        timeZone: "Asia/Tehran",
        schedules: [{
          dayOfWeek: schedule.dayOfWeek,
          localTime: schedule.localTime,
        }],
      });
      const doses = await doseStore.listDoseOccurrences(
        appUserId,
        schedule.date,
        schedule.date,
      );
      assertEquals(doses.length, 1);

      const women = createWomenCalendarStore(databaseUrl);
      await women.updateOwnerProfile(appUserId, {
        version: 0,
        enabled: true,
        lastPeriodStart: schedule.date,
        cycleLength: 28,
        periodLength: 5,
        remindersEnabled: true,
      });

      await proveRawLinkageIsRetired(sql, {
        authSubject,
        providerSubject,
        appUserId,
        accountId,
        personId,
        medicationId: String(medication.id),
        treatmentId: String(treatment.id),
        doseId: String(doses[0].id),
      });

      // Pseudonymous Account -> Person -> healthcare linkage remains visible.
      // This is explicitly residual risk, not an anonymity claim.
      const pseudonymousGraph = await sql`
        select count(*)::int as count
        from identity.accounts a
        join core.account_person_links l
          on l.account_id=a.id
         and l.link_type='Self'
         and l.status='Active'
        join lifemate.treatment_plans t
          on t.patient_person_id=l.person_id
        where a.id=${accountId}::uuid
          and t.id=${String(treatment.id)}::uuid
      `;
      assertEquals(Number(pseudonymousGraph[0]?.count), 1);

      const dump = await applicationSchemaDataDump(databaseUrl);
      for (
        const forbidden of [
          authSubject,
          providerSubject,
          email,
          email.toLowerCase(),
          phone,
          tokenKey,
          providerHandleKey,
          contactEncryptionKey,
          contactHashSecret,
        ]
      ) {
        assertEquals(
          dump.includes(forbidden),
          false,
          "Application-schema logical dump contained forbidden raw identity/key material.",
        );
      }

      const protectedRows = await sql`
        select
          (select count(*)::int
           from identity.external_identity_tokens
           where account_id=${accountId}::uuid and status='Active') as tokens,
          (select count(*)::int
           from identity.provider_identity_handles
           where account_id=${accountId}::uuid and status='Active') as handles,
          (select count(*)::int
           from identity.contact_points
           where account_id=${accountId}::uuid and status<>'Revoked') as contacts
      `;
      assertEquals(Number(protectedRows[0]?.tokens) >= 2, true);
      assertEquals(Number(protectedRows[0]?.handles) >= 1, true);
      assertEquals(Number(protectedRows[0]?.contacts), 2);

      const accountCountBefore = await sql`
        select count(*)::int as count from identity.accounts
      `;
      Deno.env.delete("LIFEMATE_IDENTITY_LINK_KEY");
      await assertRejects(
        async () => {
          const locked = createLifeMateDatabase(databaseUrl, contactHashSecret);
          await locked.requireIdentity(auth);
        },
        Error,
      );
      const accountCountAfter = await sql`
        select count(*)::int as count from identity.accounts
      `;
      assertEquals(
        Number(accountCountAfter[0]?.count),
        Number(accountCountBefore[0]?.count),
      );
    } finally {
      await closeLifeMateSqlClientsForTest().catch(() => undefined);
      for (const name of envNames) {
        const value = previous.get(name);
        if (value === undefined) Deno.env.delete(name);
        else Deno.env.set(name, value);
      }
      await sql.end({ timeout: 5 }).catch(() => undefined);
    }
  },
});

async function remapBootstrapIdentity(
  sql: ReturnType<typeof postgres>,
  options: {
    appUserId: string;
    bootstrapAccountId: string;
    accountId: string;
    personId: string;
  },
): Promise<void> {
  const bootstrapPersonRows = await sql`
    select person_id::text as person_id
    from core.account_person_links
    where account_id=${options.bootstrapAccountId}::uuid
      and link_type='Self'
      and status='Active'
  `;
  const bootstrapPersonId = String(bootstrapPersonRows[0]?.person_id ?? "");
  if (!bootstrapPersonId) {
    throw new Error("Synthetic breach bootstrap Person missing.");
  }

  await sql.begin(async (tx) => {
    await tx`
      update identity.accounts
      set legacy_app_user_id=null,updated_at_utc=now()
      where id=${options.bootstrapAccountId}::uuid
    `;
    await tx`
      insert into identity.accounts(
        id,legacy_app_user_id,status,created_at_utc,updated_at_utc
      ) values(
        ${options.accountId}::uuid,${options.appUserId}::uuid,
        'Active',now(),now()
      )
    `;
    await tx`
      insert into core.persons(id,status,subject_category)
      values(${options.personId}::uuid,'Active','Adult')
    `;
    await tx`
      insert into core.account_person_links(
        account_id,person_id,link_type,status,created_at_utc
      ) values(
        ${options.accountId}::uuid,${options.personId}::uuid,
        'Self','Active',now()
      )
    `;
    await tx`
      insert into core.person_profiles(
        person_id,display_name,locale,time_zone,avatar_key,
        profile_photo_path,created_at_utc,updated_at_utc
      )
      select ${options.personId}::uuid,display_name,locale,time_zone,
             avatar_key,profile_photo_path,created_at_utc,updated_at_utc
      from core.person_profiles
      where person_id=${bootstrapPersonId}::uuid
    `;
    await tx`
      update identity.external_identity_tokens
      set account_id=${options.accountId}::uuid
      where account_id=${options.bootstrapAccountId}::uuid
    `;
    await tx`
      update identity.provider_identity_handles
      set account_id=${options.accountId}::uuid
      where account_id=${options.bootstrapAccountId}::uuid
    `;
    await tx`
      update identity.contact_points
      set account_id=${options.accountId}::uuid,updated_at_utc=now()
      where account_id=${options.bootstrapAccountId}::uuid
    `;
    await tx`
      update identity.external_identities
      set account_id=${options.accountId}::uuid
      where account_id=${options.bootstrapAccountId}::uuid
    `;
  });
}

function configurePostRetirementIdentity(options: {
  tokenKey: string;
  providerHandleKey: string;
  contactEncryptionKey: string;
}): void {
  Deno.env.set("LIFEMATE_IDENTITY_LINK_LOOKUP_MODE", "token-only");
  Deno.env.set("LIFEMATE_IDENTITY_LINK_DUAL_WRITE", "true");
  Deno.env.set("LIFEMATE_IDENTITY_LINK_KEY", options.tokenKey);
  Deno.env.set("LIFEMATE_IDENTITY_LINK_KEY_VERSION", "71");
  Deno.env.set("LIFEMATE_IDENTITY_PROVIDER_HANDLE_DUAL_WRITE", "true");
  Deno.env.set(
    "LIFEMATE_IDENTITY_PROVIDER_HANDLE_KEY",
    options.providerHandleKey,
  );
  Deno.env.set("LIFEMATE_IDENTITY_PROVIDER_HANDLE_KEY_VERSION", "72");
  Deno.env.set("LIFEMATE_IDENTITY_LINK_RAW_RETIREMENT", "true");
  Deno.env.set("LIFEMATE_PROFILE_CONTACT_LOOKUP_MODE", "contact-only");
  Deno.env.set("LIFEMATE_IDENTITY_CONTACT_READINESS_APPROVED", "true");
  Deno.env.set("LIFEMATE_IDENTITY_CONTACT_DUAL_WRITE", "true");
  Deno.env.set("LIFEMATE_IDENTITY_CONTACT_RAW_RETIREMENT", "true");
  Deno.env.set(
    "LIFEMATE_IDENTITY_CONTACT_ENCRYPTION_KEY",
    options.contactEncryptionKey,
  );
  Deno.env.set("LIFEMATE_IDENTITY_CONTACT_ENCRYPTION_KEY_VERSION", "73");
}

async function proveRawLinkageIsRetired(
  sql: ReturnType<typeof postgres>,
  fixture: {
    authSubject: string;
    providerSubject: string;
    appUserId: string;
    accountId: string;
    personId: string;
    medicationId: string;
    treatmentId: string;
    doseId: string;
  },
): Promise<void> {
  const raw = await sql`
    select
      (select count(*)::int from lifemate.app_users
       where auth_subject=${fixture.authSubject}) as auth_subjects,
      (select count(*)::int from identity.external_identities
       where provider_subject in (${fixture.authSubject},${fixture.providerSubject}))
        as provider_subjects,
      (select count(*)::int from lifemate.user_profiles
       where user_id=${fixture.appUserId}::uuid
         and (email is not null or phone_number is not null)) as raw_contacts,
      (select count(*)::int from lifemate.medications
       where id=${fixture.medicationId}::uuid and owner_user_id is not null)
        as medication_links,
      (select count(*)::int from lifemate.treatment_plans
       where id=${fixture.treatmentId}::uuid and patient_user_id is not null)
        as treatment_links,
      (select count(*)::int from lifemate.dose_occurrences
       where id=${fixture.doseId}::uuid and patient_user_id is not null)
        as dose_links,
      (select count(*)::int from lifemate.women_calendar_profiles
       where owner_person_id=${fixture.personId}::uuid
         and owner_user_id is not null) as women_links
  `;
  for (const value of Object.values(raw[0] ?? {})) {
    assertEquals(Number(value), 0);
  }

  const directAuthJoin = await sql`
    select count(*)::int as count
    from lifemate.app_users u
    join identity.accounts a on a.legacy_app_user_id=u.id
    join core.account_person_links l
      on l.account_id=a.id and l.link_type='Self' and l.status='Active'
    join lifemate.treatment_plans t on t.patient_person_id=l.person_id
    where u.auth_subject=${fixture.authSubject}
      and t.id=${fixture.treatmentId}::uuid
  `;
  assertEquals(Number(directAuthJoin[0]?.count), 0);

  const directProviderJoin = await sql`
    select count(*)::int as count
    from identity.external_identities e
    join core.account_person_links l
      on l.account_id=e.account_id and l.link_type='Self' and l.status='Active'
    join lifemate.treatment_plans t on t.patient_person_id=l.person_id
    where e.provider_subject in (${fixture.authSubject},${fixture.providerSubject})
      and t.id=${fixture.treatmentId}::uuid
  `;
  assertEquals(Number(directProviderJoin[0]?.count), 0);
}

async function applicationSchemaDataDump(url: string): Promise<string> {
  const result = await new Deno.Command("pg_dump", {
    args: [
      "--data-only",
      "--no-owner",
      "--no-privileges",
      "--schema=identity",
      "--schema=core",
      "--schema=lifemate",
      url,
    ],
    stdout: "piped",
    stderr: "piped",
  }).output();
  if (!result.success) {
    throw new Error(
      `Synthetic application-schema pg_dump failed with exit code ${result.code}.`,
    );
  }
  return new TextDecoder().decode(result.stdout);
}

function assertAllDifferent(...values: string[]): void {
  assertEquals(new Set(values).size, values.length);
}

function futureLocalSchedule(): {
  date: string;
  dayOfWeek: string;
  localTime: string;
} {
  const future = new Date(Date.now() + 3 * 24 * 60 * 60 * 1000);
  const formatter = new Intl.DateTimeFormat("en-CA", {
    timeZone: "Asia/Tehran",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    weekday: "long",
  });
  const parts = Object.fromEntries(
    formatter.formatToParts(future).map((part) => [part.type, part.value]),
  );
  return {
    date: `${parts.year}-${parts.month}-${parts.day}`,
    dayOfWeek: parts.weekday,
    localTime: "09:00",
  };
}

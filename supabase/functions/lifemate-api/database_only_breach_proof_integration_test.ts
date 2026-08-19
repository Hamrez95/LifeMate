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
    const admin = postgres(databaseUrl, {
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
    const tokenKeyVersion = 71;
    const providerHandleKeyVersion = 72;
    const contactKeyVersion = 73;
    const auth: AuthUser = {
      id: authSubject,
      email,
      phone,
      userMetadata: {},
    };

    let appUserId: string | null = null;
    let accountId: string | null = null;
    let personId: string | null = null;
    let medicationId: string | null = null;
    let treatmentPlanId: string | null = null;
    let doseId: string | null = null;
    let episodeId: string | null = null;
    let dailyLogId: string | null = null;

    try {
      configurePostRetirementIdentity({
        tokenKey,
        tokenKeyVersion,
        providerHandleKey,
        providerHandleKeyVersion,
        contactEncryptionKey,
        contactKeyVersion,
      });

      const db = createLifeMateDatabase(databaseUrl, contactHashSecret);
      await db.bootstrapUser(auth, {
        displayName: "Synthetic Breach Fixture",
        locale: "fa",
        timeZone: "Asia/Tehran",
      });
      const identity = await db.requireIdentity(auth);
      appUserId = identity.appUserId;

      const accountRows = await admin`
        select identity.account_id_for_legacy_app_user(${appUserId}::uuid)::text
          as account_id
      `;
      accountId = String(accountRows[0]?.account_id ?? "");
      if (!accountId) throw new Error("Synthetic breach Account missing.");

      const personRows = await admin`
        select person_id::text as person_id
        from core.account_person_links
        where account_id=${accountId}::uuid
          and link_type='Self'
          and status='Active'
      `;
      personId = String(personRows[0]?.person_id ?? "");
      if (!personId) throw new Error("Synthetic breach Person missing.");
      assertNotEqualIdentifiers(authSubject, appUserId, accountId, personId);

      const bridge = createIdentityBridge(databaseUrl);
      const providers = await bridge.syncExternalIdentities(appUserId, {
        id: authSubject,
        identities: [{
          provider: "google",
          identity_data: { sub: providerSubject },
          created_at: new Date().toISOString(),
          last_sign_in_at: new Date().toISOString(),
        }],
      });
      assertEquals(providers, ["google"]);

      const medicationStore = createPersonMedicationStore(databaseUrl);
      const treatmentStore = createPersonTreatmentPlanStore(databaseUrl);
      const doseStore = createPersonDoseOccurrenceStore(databaseUrl);
      const schedule = futureLocalSchedule();

      const medication = await medicationStore.createMedication(appUserId, {
        name: "Synthetic fixture medicine",
        strengthText: "10 mg",
        form: "tablet",
        notes: null,
      });
      medicationId = String(medication.id);
      const treatment = await treatmentStore.createTreatmentPlan(appUserId, {
        medicationId,
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
      treatmentPlanId = String(treatment.id);
      const doses = await doseStore.listDoseOccurrences(
        appUserId,
        schedule.date,
        schedule.date,
      );
      assertEquals(doses.length, 1);
      doseId = String(doses[0].id);

      const women = createWomenCalendarStore(databaseUrl);
      const profile = await women.updateOwnerProfile(appUserId, {
        version: 0,
        enabled: true,
        lastPeriodStart: schedule.date,
        cycleLength: 28,
        periodLength: 5,
        remindersEnabled: true,
      });
      assertEquals(profile.ownerUserId, appUserId);
      const episode = await women.createOwnerEpisode(appUserId, {
        startedOn: schedule.date,
        endedOn: schedule.date,
        privateNotes: null,
      });
      episodeId = String(episode.id);
      const daily = await women.upsertOwnerDailyLog(appUserId, {
        version: 0,
        loggedOn: schedule.date,
        mood: "good",
        energyLevel: 4,
        painLevel: 0,
        symptoms: ["no_symptom"],
        privateNotes: null,
        shareSummaryWithCompanion: false,
      });
      dailyLogId = String(daily.id);

      await proveRawIdentityAndContactLinksAreRetired(admin, {
        authSubject,
        providerSubject,
        email,
        phone,
        appUserId,
        accountId,
        personId,
        medicationId,
        treatmentPlanId,
        doseId,
        episodeId,
        dailyLogId,
      });

      // The pseudonymous Account -> Person -> healthcare graph remains visible.
      // This is an explicit residual risk, not a claimed anonymity boundary.
      const pseudonymousGraph = await admin`
        select count(*)::int as count
        from identity.accounts a
        join core.account_person_links l
          on l.account_id=a.id
         and l.link_type='Self'
         and l.status='Active'
        join lifemate.treatment_plans t
          on t.patient_person_id=l.person_id
        where a.id=${accountId}::uuid
          and t.id=${treatmentPlanId}::uuid
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

      // A stolen database still contains opaque tokens, encrypted handles and
      // encrypted contacts, but never the external keys needed to reverse them.
      const protectedRows = await admin`
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

      // Losing the identity-link key fails closed before a second Account can be
      // created or raw-subject fallback can be used.
      const accountCountBefore = await admin`
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
      const accountCountAfter = await admin`
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
      await admin.end({ timeout: 5 }).catch(() => undefined);
    }
  },
});

function configurePostRetirementIdentity(options: {
  tokenKey: string;
  tokenKeyVersion: number;
  providerHandleKey: string;
  providerHandleKeyVersion: number;
  contactEncryptionKey: string;
  contactKeyVersion: number;
}): void {
  Deno.env.set("LIFEMATE_IDENTITY_LINK_LOOKUP_MODE", "token-only");
  Deno.env.set("LIFEMATE_IDENTITY_LINK_DUAL_WRITE", "true");
  Deno.env.set("LIFEMATE_IDENTITY_LINK_KEY", options.tokenKey);
  Deno.env.set(
    "LIFEMATE_IDENTITY_LINK_KEY_VERSION",
    String(options.tokenKeyVersion),
  );
  Deno.env.set("LIFEMATE_IDENTITY_PROVIDER_HANDLE_DUAL_WRITE", "true");
  Deno.env.set(
    "LIFEMATE_IDENTITY_PROVIDER_HANDLE_KEY",
    options.providerHandleKey,
  );
  Deno.env.set(
    "LIFEMATE_IDENTITY_PROVIDER_HANDLE_KEY_VERSION",
    String(options.providerHandleKeyVersion),
  );
  Deno.env.set("LIFEMATE_IDENTITY_LINK_RAW_RETIREMENT", "true");

  Deno.env.set("LIFEMATE_PROFILE_CONTACT_LOOKUP_MODE", "contact-only");
  Deno.env.set("LIFEMATE_IDENTITY_CONTACT_READINESS_APPROVED", "true");
  Deno.env.set("LIFEMATE_IDENTITY_CONTACT_DUAL_WRITE", "true");
  Deno.env.set("LIFEMATE_IDENTITY_CONTACT_RAW_RETIREMENT", "true");
  Deno.env.set(
    "LIFEMATE_IDENTITY_CONTACT_ENCRYPTION_KEY",
    options.contactEncryptionKey,
  );
  Deno.env.set(
    "LIFEMATE_IDENTITY_CONTACT_ENCRYPTION_KEY_VERSION",
    String(options.contactKeyVersion),
  );
}

async function proveRawIdentityAndContactLinksAreRetired(
  sql: ReturnType<typeof postgres>,
  fixture: {
    authSubject: string;
    providerSubject: string;
    email: string;
    phone: string;
    appUserId: string;
    accountId: string;
    personId: string;
    medicationId: string;
    treatmentPlanId: string;
    doseId: string;
    episodeId: string;
    dailyLogId: string;
  },
): Promise<void> {
  const rawIdentity = await sql`
    select
      (select count(*)::int
       from lifemate.app_users
       where auth_subject=${fixture.authSubject}) as app_subjects,
      (select count(*)::int
       from identity.external_identities
       where provider_subject in (
         ${fixture.authSubject},${fixture.providerSubject}
       )) as provider_subjects,
      (select count(*)::int
       from lifemate.user_profiles
       where user_id=${fixture.appUserId}::uuid
         and (email is not null or phone_number is not null)) as raw_contacts
  `;
  assertEquals(Number(rawIdentity[0]?.app_subjects), 0);
  assertEquals(Number(rawIdentity[0]?.provider_subjects), 0);
  assertEquals(Number(rawIdentity[0]?.raw_contacts), 0);

  const directAuthJoin = await sql`
    select count(*)::int as count
    from lifemate.app_users u
    join identity.accounts a on a.legacy_app_user_id=u.id
    join core.account_person_links l
      on l.account_id=a.id
     and l.link_type='Self'
     and l.status='Active'
    join lifemate.treatment_plans t on t.patient_person_id=l.person_id
    where u.auth_subject=${fixture.authSubject}
      and t.id=${fixture.treatmentPlanId}::uuid
  `;
  assertEquals(Number(directAuthJoin[0]?.count), 0);

  const directProviderJoin = await sql`
    select count(*)::int as count
    from identity.external_identities e
    join core.account_person_links l
      on l.account_id=e.account_id
     and l.link_type='Self'
     and l.status='Active'
    join lifemate.treatment_plans t on t.patient_person_id=l.person_id
    where e.provider_subject in (
      ${fixture.authSubject},${fixture.providerSubject}
    )
      and t.id=${fixture.treatmentPlanId}::uuid
  `;
  assertEquals(Number(directProviderJoin[0]?.count), 0);

  const legacyHealthcare = await sql`
    select
      (select count(*)::int from lifemate.medications
       where id=${fixture.medicationId}::uuid
         and owner_user_id is not null) as medications,
      (select count(*)::int from lifemate.treatment_plans
       where id=${fixture.treatmentPlanId}::uuid
         and patient_user_id is not null) as treatments,
      (select count(*)::int from lifemate.dose_occurrences
       where id=${fixture.doseId}::uuid
         and patient_user_id is not null) as doses,
      (select count(*)::int from lifemate.women_calendar_profiles
       where owner_person_id=${fixture.personId}::uuid
         and owner_user_id is not null) as women_profiles,
      (select count(*)::int from lifemate.women_calendar_episodes
       where id=${fixture.episodeId}::uuid
         and owner_user_id is not null) as women_episodes,
      (select count(*)::int from lifemate.women_calendar_daily_logs
       where id=${fixture.dailyLogId}::uuid
         and owner_user_id is not null) as women_daily_logs
  `;
  for (const value of Object.values(legacyHealthcare[0] ?? {})) {
    assertEquals(Number(value), 0);
  }
}

async function applicationSchemaDataDump(url: string): Promise<string> {
  const command = new Deno.Command("pg_dump", {
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
  });
  const result = await command.output();
  if (!result.success) {
    throw new Error(
      `Synthetic application-schema pg_dump failed with exit code ${result.code}.`,
    );
  }
  return new TextDecoder().decode(result.stdout);
}

function assertNotEqualIdentifiers(...values: string[]): void {
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
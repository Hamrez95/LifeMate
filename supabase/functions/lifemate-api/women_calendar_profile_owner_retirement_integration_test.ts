import {
  assertEquals,
  assertNotEquals,
  assertRejects,
} from "jsr:@std/assert@1.0.14";
import postgres from "postgres";
import { runWomenProfileOwnerRetirement } from "../../../tools/security/women-profile-owner-retirement.ts";
import { closeLifeMateSqlClientsForTest } from "./database_client.ts";
import { createDataExportStore } from "./data_export.ts";
import { createPersonWomenCalendarStore } from "./person_women_calendar.ts";
import { createWomenCalendarStore as createLegacyWomenCalendarStore } from "./women_calendar_legacy.ts";

const databaseUrl = Deno.env.get("TEST_DATABASE_URL");
if (!databaseUrl) {
  throw new Error(
    "TEST_DATABASE_URL is required for Women profile owner retirement tests.",
  );
}

const sql = postgres(databaseUrl, {
  max: 1,
  prepare: false,
  idle_timeout: 5,
  connect_timeout: 5,
});

type IdentityFixture = {
  appUserId: string;
  accountId: string;
  personId: string;
};

async function createUnequalIdentity(): Promise<IdentityFixture> {
  const appUserId = crypto.randomUUID();
  const accountId = crypto.randomUUID();
  const personId = crypto.randomUUID();
  assertNotEquals(appUserId, accountId);
  assertNotEquals(appUserId, personId);
  assertNotEquals(accountId, personId);

  await sql`
    insert into lifemate.app_users(
      id,auth_subject,status,created_at_utc,updated_at_utc
    ) values(
      ${appUserId}::uuid,${crypto.randomUUID()},'Active',now(),now()
    )
  `;
  await sql`
    update identity.accounts
    set legacy_app_user_id=null,updated_at_utc=now()
    where id=${appUserId}::uuid
  `;
  await sql`
    insert into identity.accounts(id,legacy_app_user_id,status)
    values(${accountId}::uuid,${appUserId}::uuid,'Active')
  `;
  await sql`
    insert into core.persons(id,status,subject_category)
    values(${personId}::uuid,'Active','Adult')
  `;
  await sql`
    insert into core.account_person_links(account_id,person_id,link_type,status)
    values(${accountId}::uuid,${personId}::uuid,'Self','Active')
  `;
  return { appUserId, accountId, personId };
}

async function cleanupIdentity(identity: IdentityFixture): Promise<void> {
  await sql`
    delete from lifemate.audit_logs
    where actor_user_id=${identity.appUserId}::uuid
       or resource_id=${identity.personId}::uuid
  `.catch(() => undefined);
  await sql`
    delete from lifemate.women_calendar_daily_logs
    where owner_person_id=${identity.personId}::uuid
  `.catch(() => undefined);
  await sql`
    delete from lifemate.women_calendar_episodes
    where owner_person_id=${identity.personId}::uuid
  `.catch(() => undefined);
  await sql`
    delete from lifemate.women_calendar_profiles
    where owner_person_id=${identity.personId}::uuid
       or owner_user_id=${identity.appUserId}::uuid
  `.catch(() => undefined);
  await sql`
    delete from core.account_person_links
    where account_id=${identity.accountId}::uuid
       or person_id=${identity.personId}::uuid
  `.catch(() => undefined);
  await sql`
    update identity.accounts
    set legacy_app_user_id=null,updated_at_utc=now()
    where id=${identity.accountId}::uuid
  `.catch(() => undefined);
  await sql`
    delete from identity.accounts where id=${identity.accountId}::uuid
  `.catch(() => undefined);
  await sql`
    delete from lifemate.app_users where id=${identity.appUserId}::uuid
  `.catch(() => undefined);
  await sql`
    delete from core.person_profiles where person_id=${identity.personId}::uuid
  `.catch(() => undefined);
  await sql`
    delete from core.persons where id=${identity.personId}::uuid
  `.catch(() => undefined);
}

function profilePayload(version: number, date: string) {
  return {
    version,
    enabled: true,
    lastPeriodStart: date,
    cycleLength: 28,
    periodLength: 5,
    remindersEnabled: true,
  };
}

Deno.test({
  name:
    "Women profile canonical writes retire AppUser and bounded scrub/rehydrate preserves rollback",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
    const canonical = await createUnequalIdentity();
    const legacy = await createUnequalIdentity();
    const personStore = createPersonWomenCalendarStore(databaseUrl);
    const legacyStore = createLegacyWomenCalendarStore(databaseUrl);
    const exporter = createDataExportStore(databaseUrl);

    try {
      const canonicalProfile = await personStore.updateOwnerProfile(
        canonical.appUserId,
        profilePayload(0, "2032-03-01"),
      );
      assertEquals(canonicalProfile.ownerUserId, canonical.appUserId);
      assertEquals(canonicalProfile.version, 1);

      const canonicalRow = await sql`
        select owner_user_id::text,owner_person_id::text,version,
               last_period_start::text,updated_at_utc::text
        from lifemate.women_calendar_profiles
        where owner_person_id=${canonical.personId}::uuid
      `;
      assertEquals(canonicalRow.length, 1);
      assertEquals(canonicalRow[0].owner_user_id, null);
      assertEquals(canonicalRow[0].owner_person_id, canonical.personId);

      const canonicalAudit = await sql`
        select actor_user_id::text,resource_id::text
        from lifemate.audit_logs
        where action='women_calendar.profile_created'
          and actor_user_id=${canonical.appUserId}::uuid
        order by created_at_utc desc
        limit 1
      `;
      assertEquals(canonicalAudit[0]?.actor_user_id, canonical.appUserId);
      assertEquals(canonicalAudit[0]?.resource_id, canonical.personId);

      // Updating a profile whose compatibility AppUser is already retired must
      // remain valid; profile audit resources are Person IDs, never "null" UUIDs.
      const updatedCanonical = await personStore.updateOwnerProfile(
        canonical.appUserId,
        profilePayload(1, "2032-03-02"),
      );
      assertEquals(updatedCanonical.version, 2);
      const canonicalAfterUpdate = await sql`
        select owner_user_id::text,owner_person_id::text
        from lifemate.women_calendar_profiles
        where owner_person_id=${canonical.personId}::uuid
      `;
      assertEquals(canonicalAfterUpdate[0]?.owner_user_id, null);
      assertEquals(
        canonicalAfterUpdate[0]?.owner_person_id,
        canonical.personId,
      );

      // Explicit rollback-compatible legacy writer: AppUser-only insert is left
      // intact by the retirement trigger, then mapped to Person by the existing
      // compatibility trigger.
      const legacyProfile = await legacyStore.updateOwnerProfile(
        legacy.appUserId,
        profilePayload(0, "2032-04-01"),
      );
      assertEquals(legacyProfile.ownerUserId, legacy.appUserId);
      const legacyBeforeScrub = await sql`
        select owner_user_id::text,owner_person_id::text,version,
               last_period_start::text,updated_at_utc::text
        from lifemate.women_calendar_profiles
        where owner_person_id=${legacy.personId}::uuid
      `;
      assertEquals(legacyBeforeScrub[0]?.owner_user_id, legacy.appUserId);
      assertEquals(legacyBeforeScrub[0]?.owner_person_id, legacy.personId);

      const readiness = await runWomenProfileOwnerRetirement({
        databaseUrl,
        operation: "readiness",
        mode: "dry-run",
        maxProfiles: 10,
      });
      assertEquals(readiness.readiness.ready, true);
      assertEquals(readiness.readiness.totalProfiles, 2);
      assertEquals(readiness.readiness.mappedProfiles, 2);
      assertEquals(readiness.readiness.linkedProfiles, 1);
      assertEquals(readiness.readiness.retiredProfiles, 1);

      const scrubDryRun = await runWomenProfileOwnerRetirement({
        databaseUrl,
        operation: "scrub",
        mode: "dry-run",
        maxProfiles: 10,
      });
      assertEquals(scrubDryRun.scannedProfiles, 1);
      assertEquals(scrubDryRun.changedProfiles, 0);

      await assertRejects(
        () =>
          runWomenProfileOwnerRetirement({
            databaseUrl,
            operation: "scrub",
            mode: "apply",
            maxProfiles: 10,
          }),
        Error,
        "SCRUB-WOMEN-PROFILE-OWNERS",
      );

      const scrub = await runWomenProfileOwnerRetirement({
        databaseUrl,
        operation: "scrub",
        mode: "apply",
        maxProfiles: 10,
        confirmation: "SCRUB-WOMEN-PROFILE-OWNERS",
      });
      assertEquals(scrub.scannedProfiles, 1);
      assertEquals(scrub.changedProfiles, 1);
      assertEquals(scrub.hasMore, false);

      const legacyAfterScrub = await sql`
        select owner_user_id::text,owner_person_id::text,version,
               last_period_start::text,updated_at_utc::text
        from lifemate.women_calendar_profiles
        where owner_person_id=${legacy.personId}::uuid
      `;
      assertEquals(legacyAfterScrub[0]?.owner_user_id, null);
      assertEquals(legacyAfterScrub[0]?.owner_person_id, legacy.personId);
      assertEquals(legacyAfterScrub[0]?.version, legacyBeforeScrub[0]?.version);
      assertEquals(
        legacyAfterScrub[0]?.last_period_start,
        legacyBeforeScrub[0]?.last_period_start,
      );
      assertEquals(
        legacyAfterScrub[0]?.updated_at_utc,
        legacyBeforeScrub[0]?.updated_at_utc,
      );

      const scrubAgain = await runWomenProfileOwnerRetirement({
        databaseUrl,
        operation: "scrub",
        mode: "apply",
        maxProfiles: 10,
        confirmation: "SCRUB-WOMEN-PROFILE-OWNERS",
      });
      assertEquals(scrubAgain.scannedProfiles, 0);
      assertEquals(scrubAgain.changedProfiles, 0);

      const postScrubRead = await personStore.getOwnerProfile(legacy.appUserId);
      assertEquals(postScrubRead.enabled, true);
      assertEquals(postScrubRead.ownerUserId, legacy.appUserId);

      const exported = await exporter.exportAccountData(legacy.appUserId);
      const encodedExport = JSON.stringify(exported);
      assertEquals(encodedExport.includes(legacy.appUserId), false);
      assertEquals(encodedExport.includes(legacy.accountId), false);
      assertEquals(encodedExport.includes(legacy.personId), false);

      const rehydrateDryRun = await runWomenProfileOwnerRetirement({
        databaseUrl,
        operation: "rehydrate",
        mode: "dry-run",
        maxProfiles: 10,
      });
      assertEquals(rehydrateDryRun.scannedProfiles, 2);
      assertEquals(rehydrateDryRun.changedProfiles, 0);

      await assertRejects(
        () =>
          runWomenProfileOwnerRetirement({
            databaseUrl,
            operation: "rehydrate",
            mode: "apply",
            maxProfiles: 10,
          }),
        Error,
        "REHYDRATE-WOMEN-PROFILE-OWNERS",
      );

      const rehydrate = await runWomenProfileOwnerRetirement({
        databaseUrl,
        operation: "rehydrate",
        mode: "apply",
        maxProfiles: 10,
        confirmation: "REHYDRATE-WOMEN-PROFILE-OWNERS",
      });
      assertEquals(rehydrate.scannedProfiles, 2);
      assertEquals(rehydrate.changedProfiles, 2);
      assertEquals(rehydrate.hasMore, false);

      const rehydratedRows = await sql`
        select owner_person_id::text,owner_user_id::text
        from lifemate.women_calendar_profiles
        where owner_person_id in (${canonical.personId}::uuid,${legacy.personId}::uuid)
        order by owner_person_id
      `;
      assertEquals(
        rehydratedRows.every((row) => row.owner_user_id != null),
        true,
      );

      // An old backend can again find/update its AppUser-keyed profile only after
      // the explicit bounded rehydration step has completed.
      const legacyRollbackUpdate = await legacyStore.updateOwnerProfile(
        legacy.appUserId,
        profilePayload(Number(legacyBeforeScrub[0]?.version), "2032-04-02"),
      );
      assertEquals(legacyRollbackUpdate.version, 2);

      const rehydrateAgain = await runWomenProfileOwnerRetirement({
        databaseUrl,
        operation: "rehydrate",
        mode: "apply",
        maxProfiles: 10,
        confirmation: "REHYDRATE-WOMEN-PROFILE-OWNERS",
      });
      assertEquals(rehydrateAgain.scannedProfiles, 0);
      assertEquals(rehydrateAgain.changedProfiles, 0);
    } finally {
      await closeLifeMateSqlClientsForTest().catch(() => undefined);
      await cleanupIdentity(canonical);
      await cleanupIdentity(legacy);
    }
  },
});

Deno.test({
  name: "Women profile owner readiness fails closed on ambiguous Self mapping",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
    const primary = await createUnequalIdentity();
    const competing = await createUnequalIdentity();
    const personStore = createPersonWomenCalendarStore(databaseUrl);
    let uniqueIndexDropped = false;

    try {
      await personStore.updateOwnerProfile(
        primary.appUserId,
        profilePayload(0, "2033-01-01"),
      );

      await sql`drop index core.uq_account_person_self_person`;
      uniqueIndexDropped = true;
      await sql`
        update core.account_person_links
        set status='Revoked',revoked_at_utc=now()
        where account_id=${competing.accountId}::uuid
          and person_id=${competing.personId}::uuid
          and link_type='Self'
      `;
      await sql`
        insert into core.account_person_links(
          account_id,person_id,link_type,status
        ) values(
          ${competing.accountId}::uuid,${primary.personId}::uuid,'Self','Active'
        )
      `;

      await assertRejects(
        () =>
          runWomenProfileOwnerRetirement({
            databaseUrl,
            operation: "readiness",
            mode: "dry-run",
            maxProfiles: 10,
          }),
        Error,
        "women_profile_owner_retirement_mapping_ambiguous",
      );
    } finally {
      await sql`
        delete from core.account_person_links
        where account_id=${competing.accountId}::uuid
          and person_id=${primary.personId}::uuid
          and link_type='Self'
      `.catch(() => undefined);
      if (uniqueIndexDropped) {
        await sql`
          create unique index if not exists uq_account_person_self_person
          on core.account_person_links(person_id)
          where link_type='Self' and status='Active'
        `.catch(() => undefined);
      }
      await closeLifeMateSqlClientsForTest().catch(() => undefined);
      await cleanupIdentity(primary);
      await cleanupIdentity(competing);
      await sql.end({ timeout: 1 }).catch(() => undefined);
    }
  },
});

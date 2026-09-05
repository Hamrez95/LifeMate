import { assertEquals, assertRejects } from "jsr:@std/assert@1.0.14";
import postgres from "postgres";
import { closeLifeMateSqlClientsForTest } from "./database_client.ts";
import {
  createPregnancyStore,
  PregnancyStoreError,
} from "./pregnancy_store.ts";

const databaseUrl = Deno.env.get("TEST_DATABASE_URL");
if (!databaseUrl) {
  throw new Error("TEST_DATABASE_URL is required for pregnancy store tests.");
}

const adminSql = postgres(databaseUrl, {
  max: 1,
  prepare: false,
  idle_timeout: 5,
  connect_timeout: 5,
});

Deno.test({
  name:
    "pregnancy episode history, idempotency, dating revisions and active uniqueness",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
    const motherPersonId = crypto.randomUUID();
    const store = createPregnancyStore(databaseUrl);
    let firstEpisodeId: string | null = null;
    let secondEpisodeId: string | null = null;

    try {
      await adminSql`
        insert into core.persons(id,status,subject_category)
        values (${motherPersonId}::uuid,'Active','Adult')
      `;

      const first = await store.createEpisode({
        motherPersonId,
        status: "active",
        method: "lmp",
        lmpDate: "2026-05-01",
        estimatedDueDate: null,
        referenceDate: null,
        gestationalAgeAtReferenceDays: null,
        idempotencyKey: "pregnancy-create-first",
      });
      firstEpisodeId = first.id;
      assertEquals(first.status, "active");
      assertEquals(first.version, 1);

      const retried = await store.createEpisode({
        motherPersonId,
        status: "active",
        method: "lmp",
        lmpDate: "2026-05-01",
        estimatedDueDate: null,
        referenceDate: null,
        gestationalAgeAtReferenceDays: null,
        idempotencyKey: "pregnancy-create-first",
      });
      assertEquals(retried.id, first.id);

      await assertRejects(
        () =>
          store.createEpisode({
            motherPersonId,
            status: "active",
            method: "lmp",
            lmpDate: "2026-06-01",
            estimatedDueDate: null,
            referenceDate: null,
            gestationalAgeAtReferenceDays: null,
            idempotencyKey: "pregnancy-create-conflicting-active",
          }),
        PregnancyStoreError,
        "active_pregnancy_exists",
      );

      const revised = await store.reviseDating({
        motherPersonId,
        episodeId: first.id,
        expectedVersion: first.version,
        dating: {
          method: "clinician_ultrasound",
          lmpDate: null,
          estimatedDueDate: null,
          referenceDate: "2026-08-01",
          gestationalAgeAtReferenceDays: 91,
        },
        source: "clinician_ultrasound",
        reasonCode: "clinician_redating",
        idempotencyKey: "pregnancy-redate-first",
      });
      assertEquals(revised.version, 2);
      assertEquals(revised.datingMethod, "clinician_ultrasound");

      const revisionRows = await adminSql`
        select revision_number,previous_dating_method,new_dating_method,
               previous_lmp_date::text,new_reference_date::text,
               new_gestational_age_at_reference_days
        from pregnancy.dating_revisions
        where episode_id=${first.id}::uuid
      `;
      assertEquals(revisionRows.length, 1);
      assertEquals(Number(revisionRows[0].revision_number), 1);
      assertEquals(revisionRows[0].previous_dating_method, "lmp");
      assertEquals(revisionRows[0].previous_lmp_date, "2026-05-01");
      assertEquals(revisionRows[0].new_dating_method, "clinician_ultrasound");
      assertEquals(revisionRows[0].new_reference_date, "2026-08-01");
      assertEquals(
        Number(revisionRows[0].new_gestational_age_at_reference_days),
        91,
      );

      const ended = await store.endEpisode({
        motherPersonId,
        episodeId: first.id,
        expectedVersion: revised.version,
        outcome: "pregnancy_loss",
        idempotencyKey: "pregnancy-end-first",
      });
      assertEquals(ended.status, "ended");
      assertEquals(ended.outcome, "pregnancy_loss");
      assertEquals(ended.version, 3);

      // A later pregnancy may become active without fabricating LMP/EDD.
      const second = await store.createEpisode({
        motherPersonId,
        status: "active",
        method: null,
        lmpDate: null,
        estimatedDueDate: null,
        referenceDate: null,
        gestationalAgeAtReferenceDays: null,
        idempotencyKey: "pregnancy-create-second",
      });
      secondEpisodeId = second.id;
      assertEquals(second.status, "active");
      assertEquals(second.datingMethod, null);
      assertEquals(
        (await store.getCurrentEpisode(motherPersonId))?.id,
        second.id,
      );
      assertEquals((await store.listHistory(motherPersonId)).length, 2);

      const schemaChecks = await adminSql`
        select
          not exists(
            select 1 from information_schema.columns
            where table_schema='pregnancy'
              and table_name='episodes'
              and column_name='current_week'
          ) as no_mutable_current_week,
          not has_table_privilege('authenticated','pregnancy.episodes','select')
            as authenticated_denied,
          not has_table_privilege('anon','pregnancy.episodes','select')
            as anon_denied
      `;
      assertEquals(schemaChecks[0].no_mutable_current_week, true);
      assertEquals(schemaChecks[0].authenticated_denied, true);
      assertEquals(schemaChecks[0].anon_denied, true);
    } finally {
      await closeLifeMateSqlClientsForTest().catch(() => undefined);
      if (firstEpisodeId || secondEpisodeId) {
        await adminSql`
          delete from pregnancy.episodes
          where mother_person_id=${motherPersonId}::uuid
        `.catch(() => undefined);
      }
      await adminSql`
        delete from core.persons where id=${motherPersonId}::uuid
      `.catch(() => undefined);
      await adminSql.end({ timeout: 1 }).catch(() => undefined);
    }
  },
});

import {
  assertEquals,
  assertNotEquals,
  assertRejects,
} from "jsr:@std/assert@1.0.14";
import postgres from "postgres";
import { createCareEventStore } from "./care_events.ts";
import { closeLifeMateSqlClientsForTest } from "./database_client.ts";
import { createPregnancyCalendarRouteHandler } from "./pregnancy_calendar.ts";
import { ApiError } from "./validation.ts";

const databaseUrl = Deno.env.get("TEST_DATABASE_URL");
if (!databaseUrl) {
  throw new Error(
    "TEST_DATABASE_URL is required for pregnancy calendar integration tests.",
  );
}

const sql = postgres(databaseUrl, {
  max: 1,
  prepare: false,
  idle_timeout: 5,
  connect_timeout: 5,
});

Deno.test({
  name:
    "pregnancy calendar creates and replays canonical care events while rejecting cross-Person links",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
    const ownerAppUserId = crypto.randomUUID();
    const ownerAccountId = crypto.randomUUID();
    const ownerPersonId = crypto.randomUUID();
    const otherAppUserId = crypto.randomUUID();
    const otherAccountId = crypto.randomUUID();
    const otherPersonId = crypto.randomUUID();
    const ownerEpisodeId = crypto.randomUUID();
    const endedEpisodeId = crypto.randomUUID();
    const targetDate = futureLocalDate();
    const outOfRangeDate = new Date(
      Date.parse(`${targetDate}T00:00:00Z`) + 32 * 24 * 60 * 60 * 1000,
    ).toISOString().slice(0, 10);
    const route = createPregnancyCalendarRouteHandler(databaseUrl);
    const careEvents = createCareEventStore(databaseUrl);
    let ownerEventId: string | null = null;
    let otherEventId: string | null = null;
    let conflictEventId: string | null = null;

    try {
      await seedIdentity(
        ownerAppUserId,
        ownerAccountId,
        ownerPersonId,
        `pregnancy-calendar-owner-${crypto.randomUUID()}`,
      );
      await seedIdentity(
        otherAppUserId,
        otherAccountId,
        otherPersonId,
        `pregnancy-calendar-other-${crypto.randomUUID()}`,
      );
      await sql`
        insert into pregnancy.episodes(
          id,mother_person_id,status,activated_at_utc,
          creation_idempotency_key_hash
        ) values (
          ${ownerEpisodeId}::uuid,${ownerPersonId}::uuid,'active',now(),
          ${crypto.randomUUID().replaceAll("-", "").repeat(2)}
        )
      `;

      const clientRequestId = crypto.randomUUID();
      const body = {
        classification: "prenatal",
        careEvent: {
          clientRequestId,
          eventType: "appointment",
          title: "Pregnancy prenatal integration fixture",
          providerName: "Synthetic clinician",
          specialty: "integration",
          reason: "Pregnancy calendar DB route verification",
          scheduledLocalDate: targetDate,
          scheduledLocalTime: "09:00",
          timeZone: "Asia/Tehran",
          patientReminderMinutesBefore: 15,
          caregiverReminderMinutesBefore: 45,
        },
      };

      const invalidClassificationRequestId = crypto.randomUUID();
      await assertApiError(
        () =>
          route({
            request: postRequest(
              "/api/v1/cocoon/pregnancy/calendar/events",
              {
                classification: "not_a_calendar_classification",
                careEvent: {
                  ...body.careEvent,
                  clientRequestId: invalidClassificationRequestId,
                },
              },
            ),
            path: "/api/v1/cocoon/pregnancy/calendar/events",
            appUserId: ownerAppUserId,
          }),
        400,
        "pregnancy_calendar_classification_invalid",
      );
      const invalidMutationRows = await sql`
        select count(*)::int as count
        from lifemate.care_events
        where patient_person_id=${ownerPersonId}::uuid
          and client_request_id=${invalidClassificationRequestId}::uuid
      `;
      assertEquals(Number(invalidMutationRows[0].count), 0);

      await assertApiError(
        () =>
          route({
            request: getRequest(
              "/api/v1/cocoon/pregnancy/calendar",
              { fromDate: targetDate, toDate: outOfRangeDate },
            ),
            path: "/api/v1/cocoon/pregnancy/calendar",
            appUserId: ownerAppUserId,
          }),
        400,
        "invalid_date_range",
      );

      const first = await route({
        request: postRequest(
          "/api/v1/cocoon/pregnancy/calendar/events",
          body,
        ),
        path: "/api/v1/cocoon/pregnancy/calendar/events",
        appUserId: ownerAppUserId,
      });
      assertEquals(first?.status, 201);
      const firstBody = await first!.json() as Record<string, unknown>;
      const firstEvent = firstBody.careEvent as Record<string, unknown>;
      ownerEventId = String(firstEvent.seriesId ?? firstEvent.id);
      assertEquals(firstBody.episodeId, ownerEpisodeId);
      assertEquals(firstBody.pregnancyClassification, "prenatal");

      const replay = await route({
        request: postRequest(
          "/api/v1/cocoon/pregnancy/calendar/events",
          body,
        ),
        path: "/api/v1/cocoon/pregnancy/calendar/events",
        appUserId: ownerAppUserId,
      });
      assertEquals(replay?.status, 201);
      const replayBody = await replay!.json() as Record<string, unknown>;
      const replayEvent = replayBody.careEvent as Record<string, unknown>;
      assertEquals(
        String(replayEvent.seriesId ?? replayEvent.id),
        ownerEventId,
      );

      const list = await route({
        request: getRequest(
          "/api/v1/cocoon/pregnancy/calendar",
          { fromDate: targetDate, toDate: targetDate },
        ),
        path: "/api/v1/cocoon/pregnancy/calendar",
        appUserId: ownerAppUserId,
      });
      assertEquals(list?.status, 200);
      const listBody = await list!.json() as Record<string, unknown>;
      assertEquals(listBody.episodeId, ownerEpisodeId);
      const items = listBody.items as Array<Record<string, unknown>>;
      assertEquals(items.length, 1);
      assertEquals(items[0].pregnancyClassification, "prenatal");
      assertEquals(String(items[0].seriesId ?? items[0].id), ownerEventId);

      const links = await sql`
        select episode_id::text,care_event_id::text,classification,
               linked_by_account_id::text
        from pregnancy.care_event_links
        where care_event_id=${ownerEventId}::uuid
      `;
      assertEquals(links.length, 1);
      assertEquals(links[0].episode_id, ownerEpisodeId);
      assertEquals(links[0].classification, "prenatal");
      assertEquals(links[0].linked_by_account_id, ownerAccountId);

      await assertApiError(
        () =>
          route({
            request: postRequest(
              "/api/v1/cocoon/pregnancy/calendar/links",
              {
                careEventId: crypto.randomUUID(),
                classification: "checkup",
              },
            ),
            path: "/api/v1/cocoon/pregnancy/calendar/links",
            appUserId: ownerAppUserId,
          }),
        404,
        "care_event_not_found",
      );

      const conflictCreated = await careEvents.createCareEvent(ownerAppUserId, {
        clientRequestId: crypto.randomUUID(),
        eventType: "appointment",
        title: "Already linked pregnancy appointment",
        providerName: "Synthetic clinician",
        specialty: "integration",
        reason: "Already-linked conflict fixture",
        scheduledLocalDate: targetDate,
        scheduledLocalTime: "10:00",
        timeZone: "Asia/Tehran",
        patientReminderMinutesBefore: 15,
        caregiverReminderMinutesBefore: 45,
      });
      conflictEventId = String(conflictCreated.seriesId ?? conflictCreated.id);
      await sql`
        insert into pregnancy.episodes(
          id,mother_person_id,status,activated_at_utc,ended_at_utc,outcome,
          creation_idempotency_key_hash
        ) values (
          ${endedEpisodeId}::uuid,${ownerPersonId}::uuid,'ended',
          now()-interval '2 days',now()-interval '1 day','other',
          ${crypto.randomUUID().replaceAll("-", "").repeat(2)}
        )
      `;
      await sql`
        insert into pregnancy.care_event_links(
          episode_id,care_event_id,classification,linked_by_account_id
        ) values (
          ${endedEpisodeId}::uuid,${conflictEventId}::uuid,'checkup',
          ${ownerAccountId}::uuid
        )
      `;
      await assertApiError(
        () =>
          route({
            request: postRequest(
              "/api/v1/cocoon/pregnancy/calendar/links",
              {
                careEventId: conflictEventId,
                classification: "ultrasound",
              },
            ),
            path: "/api/v1/cocoon/pregnancy/calendar/links",
            appUserId: ownerAppUserId,
          }),
        409,
        "care_event_already_linked",
      );
      const preservedConflictLink = await sql`
        select episode_id::text,classification
        from pregnancy.care_event_links
        where care_event_id=${conflictEventId}::uuid
      `;
      assertEquals(preservedConflictLink.length, 1);
      assertEquals(preservedConflictLink[0].episode_id, endedEpisodeId);
      assertEquals(preservedConflictLink[0].classification, "checkup");

      const otherCreated = await careEvents.createCareEvent(otherAppUserId, {
        clientRequestId: crypto.randomUUID(),
        eventType: "appointment",
        title: "Unrelated Person appointment",
        providerName: "Synthetic clinician",
        specialty: "integration",
        reason: "Cross-Person isolation fixture",
        scheduledLocalDate: targetDate,
        scheduledLocalTime: "11:00",
        timeZone: "Asia/Tehran",
        patientReminderMinutesBefore: 15,
        caregiverReminderMinutesBefore: 45,
      });
      otherEventId = String(otherCreated.seriesId ?? otherCreated.id);
      assertNotEquals(otherEventId, ownerEventId);

      await assertApiError(
        () =>
          route({
            request: postRequest(
              "/api/v1/cocoon/pregnancy/calendar/links",
              {
                careEventId: otherEventId,
                classification: "ultrasound",
              },
            ),
            path: "/api/v1/cocoon/pregnancy/calendar/links",
            appUserId: ownerAppUserId,
          }),
        404,
        "care_event_not_found",
      );

      const crossLinkCount = await sql`
        select count(*)::int as count
        from pregnancy.care_event_links
        where care_event_id=${otherEventId}::uuid
      `;
      assertEquals(Number(crossLinkCount[0].count), 0);

      await assertApiError(
        () =>
          route({
            request: getRequest(
              "/api/v1/cocoon/pregnancy/calendar",
              { fromDate: targetDate, toDate: targetDate },
            ),
            path: "/api/v1/cocoon/pregnancy/calendar",
            appUserId: otherAppUserId,
          }),
        409,
        "active_pregnancy_required",
      );

      const ownerEventRows = await sql`
        select patient_person_id::text
        from lifemate.care_events
        where id=${ownerEventId}::uuid
      `;
      assertEquals(ownerEventRows.length, 1);
      assertEquals(ownerEventRows[0].patient_person_id, ownerPersonId);
    } finally {
      await closeLifeMateSqlClientsForTest().catch(() => undefined);
      await sql`
        delete from pregnancy.episodes
        where mother_person_id in (
          ${ownerPersonId}::uuid,${otherPersonId}::uuid
        )
      `.catch(() => undefined);
      for (
        const eventId of [ownerEventId, otherEventId, conflictEventId]
      ) {
        if (!eventId) continue;
        await sql`
          delete from lifemate.audit_logs
          where resource_type='care_event'
            and resource_id=${eventId}::uuid
        `.catch(() => undefined);
        await sql`
          delete from lifemate.care_events where id=${eventId}::uuid
        `.catch(() => undefined);
      }
      await cleanupIdentity(
        ownerAppUserId,
        ownerAccountId,
        ownerPersonId,
      );
      await cleanupIdentity(
        otherAppUserId,
        otherAccountId,
        otherPersonId,
      );
    }
  },
});

function postRequest(
  path: string,
  body: Record<string, unknown>,
): Request {
  return new Request(`https://lifemate.test${path}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
}

function getRequest(
  path: string,
  query: Record<string, string>,
): Request {
  const url = new URL(`https://lifemate.test${path}`);
  for (const [key, value] of Object.entries(query)) {
    url.searchParams.set(key, value);
  }
  return new Request(url);
}

function futureLocalDate(): string {
  const future = new Date(Date.now() + 2 * 24 * 60 * 60 * 1000);
  const formatter = new Intl.DateTimeFormat("en-CA", {
    timeZone: "Asia/Tehran",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  });
  const parts = Object.fromEntries(
    formatter.formatToParts(future).map((part) => [part.type, part.value]),
  );
  return `${parts.year}-${parts.month}-${parts.day}`;
}

async function seedIdentity(
  appUserId: string,
  accountId: string,
  personId: string,
  authSubject: string,
): Promise<void> {
  await sql`
    insert into lifemate.app_users(
      id,auth_subject,status,created_at_utc,updated_at_utc
    ) values (
      ${appUserId}::uuid,${authSubject},'Active',now(),now()
    )
  `;
  await sql`
    update identity.accounts
    set legacy_app_user_id=null,updated_at_utc=now()
    where id=${appUserId}::uuid
  `;
  await sql`
    insert into identity.accounts(
      id,legacy_app_user_id,status,created_at_utc,updated_at_utc
    ) values (
      ${accountId}::uuid,${appUserId}::uuid,'Active',now(),now()
    )
  `;
  await sql`
    insert into core.persons(id,status,subject_category)
    values(${personId}::uuid,'Active','Adult')
  `;
  await sql`
    insert into core.account_person_links(
      account_id,person_id,link_type,status,created_at_utc
    ) values (
      ${accountId}::uuid,${personId}::uuid,'Self','Active',now()
    )
  `;
}

async function cleanupIdentity(
  appUserId: string,
  accountId: string,
  personId: string,
): Promise<void> {
  await sql`
    delete from commerce.entitlements
    where grantee_account_id in (${appUserId}::uuid,${accountId}::uuid)
       or beneficiary_person_id in (${appUserId}::uuid,${personId}::uuid)
  `.catch(() => undefined);
  await sql`
    delete from ecosystem.app_enrollments
    where account_id in (${appUserId}::uuid,${accountId}::uuid)
  `.catch(() => undefined);
  await sql`
    delete from identity.external_identities
    where account_id in (${appUserId}::uuid,${accountId}::uuid)
  `.catch(() => undefined);
  await sql`
    delete from core.account_person_links
    where account_id in (${appUserId}::uuid,${accountId}::uuid)
       or person_id in (${appUserId}::uuid,${personId}::uuid)
  `.catch(() => undefined);
  await sql`
    delete from core.person_profiles
    where person_id in (${appUserId}::uuid,${personId}::uuid)
  `.catch(() => undefined);
  await sql`
    delete from core.persons
    where id in (${appUserId}::uuid,${personId}::uuid)
  `.catch(() => undefined);
  await sql`
    update identity.accounts
    set legacy_app_user_id=null,updated_at_utc=now()
    where id in (${appUserId}::uuid,${accountId}::uuid)
  `.catch(() => undefined);
  await sql`
    delete from identity.accounts
    where id in (${appUserId}::uuid,${accountId}::uuid)
  `.catch(() => undefined);
  await sql`
    delete from lifemate.app_users where id=${appUserId}::uuid
  `.catch(() => undefined);
}

async function assertApiError(
  action: () => Promise<unknown>,
  status: number,
  code: string,
): Promise<void> {
  const error = await assertRejects(action, ApiError);
  assertEquals(error.status, status);
  assertEquals(error.code, code);
}

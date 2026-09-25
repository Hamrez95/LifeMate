import { createCareEventStore } from "./care_events.ts";
import { createCocoonIdentityResolver } from "./cocoon_identity.ts";
import { getLifeMateSql } from "./database_client.ts";
import { json } from "./http.ts";
import { createPregnancyAuthorization } from "./pregnancy_authorization.ts";
import { createPregnancyStore } from "./pregnancy_store.ts";
import {
  ApiError,
  readJsonObject,
  requiredDate,
  requiredUuid,
  validateRange,
} from "./validation.ts";

type CalendarClassification =
  | "prenatal"
  | "ultrasound"
  | "checkup"
  | "lab_test"
  | "injection"
  | "other";

type CalendarLink = {
  careEventId: string;
  classification: CalendarClassification;
};

type CalendarMutationContext = {
  accountId: string;
  personId: string;
  episodeId: string;
};

const supportedClassifications = new Set<CalendarClassification>([
  "prenatal",
  "ultrasound",
  "checkup",
  "lab_test",
  "injection",
  "other",
]);

export function normalizePregnancyCalendarClassification(
  value: unknown,
): CalendarClassification {
  const normalized = String(value ?? "").trim().toLowerCase();
  if (!supportedClassifications.has(normalized as CalendarClassification)) {
    throw new ApiError(
      400,
      "pregnancy_calendar_classification_invalid",
      "Pregnancy calendar classification is invalid.",
    );
  }
  return normalized as CalendarClassification;
}

export function createPregnancyCalendarRouteHandler(databaseUrl: string) {
  const sql = getLifeMateSql(databaseUrl);
  const identity = createCocoonIdentityResolver(databaseUrl);
  const pregnancy = createPregnancyStore(databaseUrl);
  const authorization = createPregnancyAuthorization(databaseUrl);
  const careEvents = createCareEventStore(databaseUrl);

  async function context(appUserId: string, manage: boolean) {
    const { accountId, personId } = await identity.resolve(appUserId);
    const episode = await pregnancy.getCurrentEpisode(personId);
    if (!episode || episode.status !== "active") {
      throw new ApiError(
        409,
        "active_pregnancy_required",
        "An active pregnancy is required.",
      );
    }
    await authorization.requireAccess({
      callerAccountId: accountId,
      subjectPersonId: personId,
      episodeId: episode.id,
      scope: manage ? "pregnancy.owner.manage" : "pregnancy.summary.read",
    });
    return { accountId, personId, episode };
  }

  async function mutationContext(
    connection: any,
    appUserId: string,
  ): Promise<CalendarMutationContext> {
    const identityRows = await connection`
      select
        identity.account_id_for_legacy_app_user(${appUserId}::uuid)::text
          as account_id,
        core.self_person_id_for_legacy_app_user(${appUserId}::uuid)::text
          as person_id
    `;
    const accountId = identityRows[0]?.account_id == null
      ? null
      : String(identityRows[0].account_id);
    const personId = identityRows[0]?.person_id == null
      ? null
      : String(identityRows[0].person_id);
    if (!accountId || !personId) {
      throw new ApiError(
        409,
        "cocoon_person_context_missing",
        "Cocoon person context is not ready.",
      );
    }

    const rows = await connection`
      select id::text
      from pregnancy.episodes
      where mother_person_id=${personId}::uuid
        and status='active'
      order by activated_at_utc desc,id
      limit 1
      for update
    `;
    const episodeId = rows[0]?.id == null ? null : String(rows[0].id);
    if (!episodeId) {
      throw new ApiError(
        409,
        "active_pregnancy_required",
        "An active pregnancy is required.",
      );
    }

    const accessRows = await connection`
      select security.can_access_pregnancy_scope(
        ${accountId}::uuid,
        ${personId}::uuid,
        ${episodeId}::uuid,
        'pregnancy.owner.manage'::varchar,
        now()
      ) as allowed
    `;
    if (accessRows[0]?.allowed !== true) {
      throw new ApiError(
        403,
        "pregnancy_access_denied",
        "Pregnancy access is not authorized.",
      );
    }
    return { accountId, personId, episodeId };
  }

  async function linksForEpisode(episodeId: string): Promise<CalendarLink[]> {
    const rows = await sql`
      select care_event_id::text, classification
      from pregnancy.care_event_links
      where episode_id=${episodeId}::uuid
    `;
    return rows.map((row) => ({
      careEventId: String(row.care_event_id),
      classification: normalizePregnancyCalendarClassification(
        row.classification,
      ),
    }));
  }

  async function linkExistingWithContext(
    connection: any,
    mutation: CalendarMutationContext,
    careEventId: string,
    classification: CalendarClassification,
  ) {
    const events = await connection`
      select id
      from lifemate.care_events
      where id=${careEventId}::uuid
        and patient_person_id=${mutation.personId}::uuid
      for update
    `;
    if (!events[0]) {
      throw new ApiError(
        404,
        "care_event_not_found",
        "Care event was not found.",
      );
    }
    const existing = await connection`
      select episode_id::text,classification
      from pregnancy.care_event_links
      where care_event_id=${careEventId}::uuid
      for update
    `;
    if (
      existing[0] &&
      String(existing[0].episode_id) !== mutation.episodeId
    ) {
      throw new ApiError(
        409,
        "care_event_already_linked",
        "Care event is already associated with another pregnancy.",
      );
    }
    const rows = await connection`
      insert into pregnancy.care_event_links
        (episode_id,care_event_id,classification,linked_by_account_id)
      values
        (${mutation.episodeId}::uuid,${careEventId}::uuid,${classification},
         ${mutation.accountId}::uuid)
      on conflict (episode_id,care_event_id) do update
        set classification=excluded.classification,
            updated_at_utc=now()
      returning episode_id::text,care_event_id::text,classification,
                created_at_utc,updated_at_utc
    `;
    return rows[0];
  }

  async function linkExisting(
    appUserId: string,
    careEventIdValue: unknown,
    classificationValue: unknown,
  ) {
    const careEventId = requiredUuid(careEventIdValue, "careEventId");
    const classification = normalizePregnancyCalendarClassification(
      classificationValue,
    );
    return await sql.begin(async (tx: any) => {
      const mutation = await mutationContext(tx, appUserId);
      return await linkExistingWithContext(
        tx,
        mutation,
        careEventId,
        classification,
      );
    });
  }

  async function createEvent(
    appUserId: string,
    careEventBody: Record<string, unknown>,
    classificationValue: unknown,
  ) {
    const classification = normalizePregnancyCalendarClassification(
      classificationValue,
    );
    return await sql.begin(async (tx: any) => {
      const mutation = await mutationContext(tx, appUserId);
      const created = await careEvents.createCareEventWithConnection(
        tx,
        appUserId,
        careEventBody,
      );
      const seriesId = requiredUuid(
        created.seriesId ?? created.id,
        "careEventId",
      );
      const link = await linkExistingWithContext(
        tx,
        mutation,
        seriesId,
        classification,
      );
      return {
        contractVersion: 1,
        episodeId: String(link.episode_id),
        pregnancyClassification: String(link.classification),
        careEvent: created,
      };
    });
  }

  return async ({
    request,
    path,
    appUserId,
  }: {
    request: Request;
    path: string;
    appUserId: string;
  }): Promise<Response | null> => {
    if (
      request.method === "GET" && path === "/api/v1/cocoon/pregnancy/calendar"
    ) {
      const url = new URL(request.url);
      const fromDate = requiredDate(
        url.searchParams.get("fromDate"),
        "fromDate",
      );
      const toDate = requiredDate(url.searchParams.get("toDate"), "toDate");
      validateRange(fromDate, toDate, 31);
      const { episode } = await context(appUserId, false);
      const links = await linksForEpisode(episode.id);
      const bySeries = new Map(
        links.map((link) => [link.careEventId, link.classification]),
      );
      const canonical = await careEvents.listCareEvents(
        appUserId,
        fromDate,
        toDate,
      );
      const items = canonical.flatMap((event) => {
        const seriesId = String(event.seriesId ?? event.id ?? "");
        const classification = bySeries.get(seriesId);
        return classification == null
          ? []
          : [{ ...event, pregnancyClassification: classification }];
      });
      return json({
        contractVersion: 1,
        episodeId: episode.id,
        fromDate,
        toDate,
        items,
      });
    }

    if (
      request.method === "POST" &&
      path === "/api/v1/cocoon/pregnancy/calendar/events"
    ) {
      const body = await readJsonObject(request);
      const careEventBody = body.careEvent;
      if (
        !careEventBody ||
        typeof careEventBody !== "object" ||
        Array.isArray(careEventBody)
      ) {
        throw new ApiError(
          400,
          "pregnancy_calendar_care_event_invalid",
          "A canonical care event payload is required.",
        );
      }
      return json(
        await createEvent(
          appUserId,
          careEventBody as Record<string, unknown>,
          body.classification,
        ),
        201,
      );
    }

    if (
      request.method === "POST" &&
      path === "/api/v1/cocoon/pregnancy/calendar/links"
    ) {
      const body = await readJsonObject(request);
      const link = await linkExisting(
        appUserId,
        body.careEventId,
        body.classification,
      );
      return json({
        contractVersion: 1,
        episodeId: String(link.episode_id),
        careEventId: String(link.care_event_id),
        pregnancyClassification: String(link.classification),
      });
    }

    return null;
  };
}

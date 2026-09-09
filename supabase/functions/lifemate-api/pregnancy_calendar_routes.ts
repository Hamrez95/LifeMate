import { createCocoonIdentityResolver } from "./cocoon_identity.ts";
import { getLifeMateSql } from "./database_client.ts";
import { json } from "./http.ts";
import { requireMutationIdempotencyKey } from "./idempotency.ts";
import { createPersonCareEventStoreV2 } from "./person_care_events_v2.ts";
import { createPregnancyAuthorization } from "./pregnancy_authorization.ts";
import { createPregnancyStore } from "./pregnancy_store.ts";
import { ApiError } from "./validation.ts";

const careEventLinkPattern =
  /^\/api\/v1\/cocoon\/pregnancy\/care-events\/([0-9a-f-]{36})\/link$/i;
const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

function requiredCareEventId(value: string): string {
  if (!uuidPattern.test(value)) {
    throw new ApiError(
      400,
      "pregnancy_care_event_id_invalid",
      "A valid care event identifier is required.",
    );
  }
  return value;
}

export function filterLinkedPregnancyCareEvents(
  canonicalEvents: Record<string, unknown>[],
  linkedCareEventIds: ReadonlySet<string>,
): Record<string, unknown>[] {
  return canonicalEvents.filter((event) => {
    const seriesId = String(event.seriesId ?? event.id ?? "");
    return linkedCareEventIds.has(seriesId);
  });
}

export function createPregnancyCalendarRouteHandler(databaseUrl: string) {
  const sql = getLifeMateSql(databaseUrl);
  const identity = createCocoonIdentityResolver(databaseUrl);
  const pregnancy = createPregnancyStore(databaseUrl);
  const authorization = createPregnancyAuthorization(databaseUrl);
  const careEvents = createPersonCareEventStoreV2(databaseUrl);

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
      request.method === "GET" &&
      path === "/api/v1/cocoon/pregnancy/calendar"
    ) {
      const { accountId, personId } = await identity.resolve(appUserId);
      const episode = await pregnancy.getCurrentEpisode(personId);
      if (!episode) {
        return json({
          contractVersion: 1,
          episodeId: null,
          careEvents: [],
        });
      }
      await authorization.requireAccess({
        callerAccountId: accountId,
        subjectPersonId: personId,
        episodeId: episode.id,
        scope: "pregnancy.appointments.read",
      });

      const url = new URL(request.url);
      const canonical = await careEvents.listCareEvents(
        appUserId,
        url.searchParams.get("fromDate"),
        url.searchParams.get("toDate"),
      );
      const rows = await sql`
        select care_event_id::text
        from pregnancy.care_event_links
        where episode_id=${episode.id}::uuid
      `;
      const linked = new Set(rows.map((row: any) => String(row.care_event_id)));
      const visible = filterLinkedPregnancyCareEvents(canonical, linked);

      return json({
        contractVersion: 1,
        episodeId: episode.id,
        careEvents: visible,
      });
    }

    const linkMatch = path.match(careEventLinkPattern);
    if (request.method === "POST" && linkMatch) {
      const careEventId = requiredCareEventId(linkMatch[1]);
      const idempotencyKey = requireMutationIdempotencyKey(request);
      const { accountId, personId } = await identity.resolve(appUserId);
      const episode = await pregnancy.getCurrentEpisode(personId);
      if (!episode) {
        throw new ApiError(
          409,
          "pregnancy_active_episode_required",
          "An active pregnancy episode is required.",
        );
      }
      await authorization.requireAccess({
        callerAccountId: accountId,
        subjectPersonId: personId,
        episodeId: episode.id,
        scope: "pregnancy.owner.manage",
      });

      const idempotencyHash = await sha256Hex(idempotencyKey);
      const result = await sql.begin(async (tx: any) => {
        const prior = await tx`
          select care_event_id::text
          from pregnancy.care_event_links
          where episode_id=${episode.id}::uuid
            and idempotency_key_hash=${idempotencyHash}
          limit 1
        `;
        if (prior[0]) {
          if (String(prior[0].care_event_id) !== careEventId) {
            throw new ApiError(
              409,
              "idempotency_key_reused",
              "The idempotency key was already used for another care event.",
            );
          }
          return { created: false };
        }

        const ownedEvent = await tx`
          select id::text
          from lifemate.care_events
          where id=${careEventId}::uuid
            and patient_person_id=${personId}::uuid
          limit 1
          for update
        `;
        if (!ownedEvent[0]) {
          throw new ApiError(
            404,
            "pregnancy_care_event_not_found",
            "The care event is unavailable for this pregnancy.",
          );
        }

        const existing = await tx`
          select episode_id::text
          from pregnancy.care_event_links
          where care_event_id=${careEventId}::uuid
          limit 1
          for update
        `;
        if (existing[0]) {
          if (String(existing[0].episode_id) !== episode.id) {
            throw new ApiError(
              409,
              "pregnancy_care_event_already_linked",
              "The care event is already associated with another pregnancy episode.",
            );
          }
          return { created: false };
        }

        await tx`
          insert into pregnancy.care_event_links(
            episode_id,
            care_event_id,
            linked_by_account_id,
            idempotency_key_hash
          ) values (
            ${episode.id}::uuid,
            ${careEventId}::uuid,
            ${accountId}::uuid,
            ${idempotencyHash}
          )
        `;
        return { created: true };
      });

      return json({
        contractVersion: 1,
        episodeId: episode.id,
        careEventId,
        linked: true,
      }, result.created ? 201 : 200);
    }

    return null;
  };
}

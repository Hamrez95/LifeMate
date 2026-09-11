import { createCocoonIdentityResolver } from "./cocoon_identity.ts";
import { getLifeMateSql } from "./database_client.ts";
import { createHealthObservationStore } from "./health_observations.ts";
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

type MeasurementType = "weight" | "blood_pressure" | "blood_glucose";

const supportedMeasurementTypes = new Set<MeasurementType>([
  "weight",
  "blood_pressure",
  "blood_glucose",
]);

export function normalizePregnancyMeasurementType(value: unknown): MeasurementType {
  const normalized = String(value ?? "").trim().toLowerCase();
  if (!supportedMeasurementTypes.has(normalized as MeasurementType)) {
    throw new ApiError(
      400,
      "pregnancy_measurement_type_invalid",
      "Cocoon pregnancy measurements support weight, blood pressure and blood glucose.",
    );
  }
  return normalized as MeasurementType;
}

export function createPregnancyMeasurementRouteHandler(databaseUrl: string) {
  const sql = getLifeMateSql(databaseUrl);
  const identity = createCocoonIdentityResolver(databaseUrl);
  const pregnancy = createPregnancyStore(databaseUrl);
  const authorization = createPregnancyAuthorization(databaseUrl);
  const observations = createHealthObservationStore(databaseUrl);

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
      scope: manage ? "pregnancy.owner.manage" : "pregnancy.observations.read",
    });
    return { accountId, personId, episode };
  }

  async function linkExisting(
    appUserId: string,
    observationIdValue: unknown,
  ) {
    const observationId = requiredUuid(observationIdValue, "observationId");
    const { accountId, personId, episode } = await context(appUserId, true);
    return await sql.begin(async (tx: any) => {
      const rows = await tx`
        select id, observation_type
        from lifemate.health_observations
        where id=${observationId}::uuid
          and person_id=${personId}::uuid
        for update
      `;
      if (!rows[0]) {
        throw new ApiError(
          404,
          "health_observation_not_found",
          "Health observation was not found.",
        );
      }
      normalizePregnancyMeasurementType(rows[0].observation_type);

      const prior = await tx`
        select episode_id::text
        from pregnancy.observation_links
        where observation_id=${observationId}::uuid
        for update
      `;
      if (prior[0] && String(prior[0].episode_id) !== episode.id) {
        throw new ApiError(
          409,
          "observation_already_linked",
          "Health observation is already associated with another pregnancy.",
        );
      }

      const linked = await tx`
        insert into pregnancy.observation_links(
          episode_id,observation_id,linked_by_account_id
        ) values (
          ${episode.id}::uuid,${observationId}::uuid,${accountId}::uuid
        )
        on conflict (episode_id,observation_id) do nothing
        returning episode_id::text,observation_id::text,created_at_utc
      `;
      if (linked[0]) return linked[0];
      const existing = await tx`
        select episode_id::text,observation_id::text,created_at_utc
        from pregnancy.observation_links
        where episode_id=${episode.id}::uuid
          and observation_id=${observationId}::uuid
        limit 1
      `;
      return existing[0];
    });
  }

  async function listMeasurements(
    appUserId: string,
    fromDate: string,
    toDate: string,
  ) {
    const { episode } = await context(appUserId, false);
    const links = await sql`
      select observation_id::text
      from pregnancy.observation_links
      where episode_id=${episode.id}::uuid
    `;
    const linkedIds = new Set(links.map((row) => String(row.observation_id)));
    const canonical = await observations.listOwnerObservations(
      appUserId,
      fromDate,
      toDate,
    );
    const items = canonical.filter((observation) => {
      if (!linkedIds.has(String(observation.id ?? ""))) return false;
      const localDate = String(observation.observedLocalDate ?? "").slice(0, 10);
      if (localDate < fromDate || localDate > toDate) return false;
      return supportedMeasurementTypes.has(
        String(observation.observationType ?? "") as MeasurementType,
      );
    });
    return {
      contractVersion: 1,
      episodeId: episode.id,
      items,
    };
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
      request.method === "GET" &&
      path === "/api/v1/cocoon/pregnancy/measurements"
    ) {
      const url = new URL(request.url);
      const fromDate = requiredDate(url.searchParams.get("fromDate"), "fromDate");
      const toDate = requiredDate(url.searchParams.get("toDate"), "toDate");
      validateRange(fromDate, toDate, 366);
      return json(await listMeasurements(appUserId, fromDate, toDate));
    }

    if (
      request.method === "POST" &&
      path === "/api/v1/cocoon/pregnancy/measurements"
    ) {
      const body = await readJsonObject(request);
      const measurementType = normalizePregnancyMeasurementType(
        body.observationType,
      );
      const created = await observations.createOwnerObservation(
        appUserId,
        { ...body, observationType: measurementType },
        "cocoonmate",
      );
      const link = await linkExisting(appUserId, created.id);
      return json({
        contractVersion: 1,
        episodeId: String(link.episode_id),
        observation: created,
      }, 201);
    }

    if (
      request.method === "POST" &&
      path === "/api/v1/cocoon/pregnancy/measurement-links"
    ) {
      const body = await readJsonObject(request);
      const link = await linkExisting(appUserId, body.observationId);
      return json({
        contractVersion: 1,
        episodeId: String(link.episode_id),
        observationId: String(link.observation_id),
      });
    }

    return null;
  };
}

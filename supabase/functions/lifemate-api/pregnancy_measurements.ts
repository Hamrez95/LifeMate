import { createCocoonIdentityResolver } from "./cocoon_identity.ts";
import { getLifeMateSql } from "./database_client.ts";
import {
  createHealthObservationStore,
  healthObservationMetricSchema,
} from "./health_observations.ts";
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

type CreateOwnerObservation = (
  appUserId: string,
  body: Record<string, unknown>,
  trustedApplicationCode?: string,
) => Promise<Record<string, unknown>>;

type EnsureOwnerMeasurementAccess = () => Promise<void>;

const supportedMeasurementTypes = new Set<MeasurementType>([
  "weight",
  "blood_pressure",
  "blood_glucose",
]);

export function normalizePregnancyMeasurementType(
  value: unknown,
): MeasurementType {
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

type MeasurementFieldSemantic =
  | "weight"
  | "systolic"
  | "diastolic"
  | "blood_glucose";

type PregnancyMeasurementSchemaItem = {
  observationType: MeasurementType;
  fields: Array<{
    valueKey: "valuePrimary" | "valueSecondary";
    semantic: MeasurementFieldSemantic;
    unit: string;
  }>;
};

export function pregnancyMeasurementSchema(): PregnancyMeasurementSchemaItem[] {
  const weight = healthObservationMetricSchema("weight");
  const pressure = healthObservationMetricSchema("blood_pressure");
  const glucose = healthObservationMetricSchema("blood_glucose");

  if (
    weight.unitPrimary == null ||
    pressure.unitPrimary == null ||
    pressure.unitSecondary == null ||
    !pressure.hasSecondaryValue ||
    glucose.unitPrimary == null
  ) {
    throw new Error("Canonical pregnancy measurement schema is incomplete.");
  }

  return [
    {
      observationType: "weight",
      fields: [
        {
          valueKey: "valuePrimary",
          semantic: "weight",
          unit: weight.unitPrimary,
        },
      ],
    },
    {
      observationType: "blood_pressure",
      fields: [
        {
          valueKey: "valuePrimary",
          semantic: "systolic",
          unit: pressure.unitPrimary,
        },
        {
          valueKey: "valueSecondary",
          semantic: "diastolic",
          unit: pressure.unitSecondary,
        },
      ],
    },
    {
      observationType: "blood_glucose",
      fields: [
        {
          valueKey: "valuePrimary",
          semantic: "blood_glucose",
          unit: glucose.unitPrimary,
        },
      ],
    },
  ];
}

/// Delegates pregnancy measurement creation to the canonical health-observation
/// domain while fixing provenance to the trusted CocoonMate application.
/// Client-provided provenance fields cannot select the trusted application code.
export async function createPregnancyMeasurementObservation(
  ensureOwnerAccess: EnsureOwnerMeasurementAccess,
  createOwnerObservation: CreateOwnerObservation,
  appUserId: string,
  body: Record<string, unknown>,
): Promise<Record<string, unknown>> {
  // Authorization/active-episode validation must happen before the canonical
  // health observation write. Link authorization is intentionally repeated
  // afterwards so an episode/access change between the two steps still fails
  // closed while an ambiguous transport retry can recover by request id.
  await ensureOwnerAccess();
  const measurementType = normalizePregnancyMeasurementType(
    body.observationType,
  );
  return await createOwnerObservation(
    appUserId,
    { ...body, observationType: measurementType },
    "cocoonmate",
  );
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

  type OwnerMutationContext = {
    accountId: string;
    personId: string;
    episodeId: string;
  };

  async function mutationContext(
    tx: any,
    appUserId: string,
  ): Promise<OwnerMutationContext> {
    const identityRows = await tx`
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

    const episodeRows = await tx`
      select id::text
      from pregnancy.episodes
      where mother_person_id=${personId}::uuid
        and status='active'
      order by activated_at_utc desc,id
      limit 1
      for update
    `;
    const episodeId = episodeRows[0]?.id == null
      ? null
      : String(episodeRows[0].id);
    if (!episodeId) {
      throw new ApiError(
        409,
        "active_pregnancy_required",
        "An active pregnancy is required.",
      );
    }

    const accessRows = await tx`
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

  async function linkExistingInTransaction(
    tx: any,
    owner: OwnerMutationContext,
    observationIdValue: unknown,
  ) {
    const observationId = requiredUuid(observationIdValue, "observationId");
    const rows = await tx`
      select id, observation_type
      from lifemate.health_observations
      where id=${observationId}::uuid
        and person_id=${owner.personId}::uuid
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
    if (
      prior[0] &&
      String(prior[0].episode_id) !== owner.episodeId
    ) {
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
        ${owner.episodeId}::uuid,
        ${observationId}::uuid,
        ${owner.accountId}::uuid
      )
      on conflict (episode_id,observation_id) do nothing
      returning episode_id::text,observation_id::text,created_at_utc
    `;
    if (linked[0]) return linked[0];

    const existing = await tx`
      select episode_id::text,observation_id::text,created_at_utc
      from pregnancy.observation_links
      where episode_id=${owner.episodeId}::uuid
        and observation_id=${observationId}::uuid
      limit 1
    `;
    return existing[0];
  }

  async function linkExisting(
    appUserId: string,
    observationIdValue: unknown,
  ) {
    return await sql.begin(async (tx: any) => {
      const owner = await mutationContext(tx, appUserId);
      return await linkExistingInTransaction(
        tx,
        owner,
        observationIdValue,
      );
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
      const localDate = String(observation.observedLocalDate ?? "").slice(
        0,
        10,
      );
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
      path === "/api/v1/cocoon/pregnancy/measurements/schema"
    ) {
      await context(appUserId, false);
      return json({
        contractVersion: 1,
        measurementTypes: pregnancyMeasurementSchema(),
      });
    }

    if (
      request.method === "GET" &&
      path === "/api/v1/cocoon/pregnancy/measurements"
    ) {
      const url = new URL(request.url);
      const fromDate = requiredDate(
        url.searchParams.get("fromDate"),
        "fromDate",
      );
      const toDate = requiredDate(url.searchParams.get("toDate"), "toDate");
      validateRange(fromDate, toDate, 366);
      return json(await listMeasurements(appUserId, fromDate, toDate));
    }

    if (
      request.method === "POST" &&
      path === "/api/v1/cocoon/pregnancy/measurements"
    ) {
      const body = await readJsonObject(request);
      const result = await sql.begin(async (tx: any) => {
        let owner: OwnerMutationContext | null = null;
        const created = await createPregnancyMeasurementObservation(
          async () => {
            owner = await mutationContext(tx, appUserId);
          },
          (userId, normalizedBody, trustedApplicationCode) =>
            observations.createOwnerObservationInTransaction(
              tx,
              userId,
              normalizedBody,
              trustedApplicationCode,
            ),
          appUserId,
          body,
        );
        if (!owner) {
          throw new Error(
            "Pregnancy measurement owner context was not resolved.",
          );
        }
        const link = await linkExistingInTransaction(
          tx,
          owner,
          created.id,
        );
        return { created, link };
      });
      return json({
        contractVersion: 1,
        episodeId: String(result.link.episode_id),
        observation: result.created,
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

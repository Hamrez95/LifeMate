import { getLifeMateSql } from "./database_client.ts";
import {
  ApiError,
  limitedOptional,
  requiredDate,
  requiredTimestamp,
  requiredTimeZone,
  requiredUuid,
  validateRange,
} from "./validation.ts";

type Row = Record<string, any>;

type OwnerIdentity = {
  accountId: string;
  personId: string;
};

export type NormalizedHealthObservation = {
  clientRequestId: string;
  observationType:
    | "weight"
    | "height"
    | "blood_pressure"
    | "heart_rate"
    | "blood_glucose"
    | "oxygen_saturation"
    | "body_temperature"
    | "sleep_duration"
    | "note";
  valuePrimary: number | null;
  valueSecondary: number | null;
  unitPrimary: string | null;
  unitSecondary: string | null;
  note: string | null;
  observedAtUtc: Date;
  observedLocalDate: string;
  timeZone: string;
};

type MetricDefinition = {
  unitPrimary: string | null;
  unitSecondary?: string | null;
  primary?: { min: number; max: number };
  secondary?: { min: number; max: number };
};

const metricDefinitions: Record<string, MetricDefinition> = {
  weight: { unitPrimary: "kg", primary: { min: 1, max: 500 } },
  height: { unitPrimary: "cm", primary: { min: 30, max: 250 } },
  blood_pressure: {
    unitPrimary: "mmHg",
    unitSecondary: "mmHg",
    primary: { min: 40, max: 300 },
    secondary: { min: 20, max: 200 },
  },
  heart_rate: { unitPrimary: "bpm", primary: { min: 20, max: 300 } },
  blood_glucose: {
    unitPrimary: "mg/dL",
    primary: { min: 20, max: 1000 },
  },
  oxygen_saturation: {
    unitPrimary: "%",
    primary: { min: 50, max: 100 },
  },
  body_temperature: {
    unitPrimary: "°C",
    primary: { min: 25, max: 45 },
  },
  sleep_duration: {
    unitPrimary: "hours",
    primary: { min: 0, max: 24 },
  },
  note: { unitPrimary: null },
};

export function normalizeHealthObservationInput(
  body: Record<string, unknown>,
  now = new Date(),
): NormalizedHealthObservation {
  const clientRequestId = requiredUuid(body.clientRequestId, "clientRequestId");
  const observationType = String(body.observationType ?? "")
    .trim()
    .toLowerCase();
  const definition = metricDefinitions[observationType];
  if (!definition) {
    throw new ApiError(
      400,
      "invalid_observationType",
      "Unsupported health observation type.",
    );
  }

  const note = limitedOptional(body.note, "note", 500);
  const observedAtUtc = requiredTimestamp(body.observedAtUtc, "observedAtUtc");
  const observedLocalDate = requiredDate(
    body.observedLocalDate,
    "observedLocalDate",
  );
  const timeZone = requiredTimeZone(body.timeZone);

  const futureLimit = now.getTime() + 5 * 60 * 1000;
  const oldestLimit = now.getTime() - 10 * 365 * 24 * 60 * 60 * 1000;
  if (
    observedAtUtc.getTime() > futureLimit ||
    observedAtUtc.getTime() < oldestLimit
  ) {
    throw new ApiError(
      400,
      "invalid_observedAtUtc",
      "Health observation time must be within the last 10 years and not in the future.",
    );
  }

  if (observationType === "note") {
    if (!note) {
      throw new ApiError(400, "invalid_note", "A health note cannot be empty.");
    }
    return {
      clientRequestId,
      observationType: "note",
      valuePrimary: null,
      valueSecondary: null,
      unitPrimary: null,
      unitSecondary: null,
      note,
      observedAtUtc,
      observedLocalDate,
      timeZone,
    };
  }

  const valuePrimary = requiredMetricNumber(
    body.valuePrimary,
    "valuePrimary",
    definition.primary!,
  );
  const valueSecondary = definition.secondary
    ? requiredMetricNumber(
      body.valueSecondary,
      "valueSecondary",
      definition.secondary,
    )
    : null;

  if (
    observationType === "blood_pressure" &&
    valueSecondary != null &&
    valuePrimary <= valueSecondary
  ) {
    throw new ApiError(
      400,
      "invalid_blood_pressure",
      "Systolic pressure must be greater than diastolic pressure.",
    );
  }

  return {
    clientRequestId,
    observationType:
      observationType as NormalizedHealthObservation["observationType"],
    valuePrimary,
    valueSecondary,
    unitPrimary: definition.unitPrimary,
    unitSecondary: definition.unitSecondary ?? null,
    note,
    observedAtUtc,
    observedLocalDate,
    timeZone,
  };
}

function normalizeTrustedApplicationCode(value: string): string {
  const code = value.trim().toLowerCase();
  if (!/^[a-z0-9][a-z0-9_-]{1,63}$/.test(code)) {
    throw new Error("Trusted source application code is invalid.");
  }
  return code;
}

function requiredMetricNumber(
  value: unknown,
  field: string,
  range: { min: number; max: number },
): number {
  if (value == null || value === "") {
    throw new ApiError(400, `invalid_${field}`, `${field} is required.`);
  }
  const number = Number(value);
  if (!Number.isFinite(number) || number < range.min || number > range.max) {
    throw new ApiError(
      400,
      `invalid_${field}`,
      `${field} must be between ${range.min} and ${range.max}.`,
    );
  }
  return Math.round(number * 1000) / 1000;
}

export function createHealthObservationStore(databaseUrl: string) {
  const sql = getLifeMateSql(databaseUrl);

  async function resolveOwnerIdentity(
    connection: any,
    appUserId: string,
  ): Promise<OwnerIdentity> {
    const rows = await connection`
      select
        identity.account_id_for_legacy_app_user(${appUserId}::uuid)::text
          as account_id,
        core.self_person_id_for_legacy_app_user(${appUserId}::uuid)::text
          as person_id
    `;
    const accountId = rows[0]?.account_id;
    const personId = rows[0]?.person_id;
    if (
      typeof accountId !== "string" || accountId.length === 0 ||
      typeof personId !== "string" || personId.length === 0
    ) {
      // Preserve the existing public Health API error contract while resolving
      // through the canonical Account -> Self Person identity boundary.
      throw new ApiError(
        409,
        "self_person_missing",
        "A self health profile is required before recording health data.",
      );
    }
    return { accountId, personId };
  }

  async function resolveSourceApplication(
    connection: any,
    trustedApplicationCode: string,
  ): Promise<{ id: string; code: string }> {
    const applicationCode = normalizeTrustedApplicationCode(
      trustedApplicationCode,
    );
    const rows = await connection`
      select id, code
      from ecosystem.applications
      where code = ${applicationCode}
        and status = 'Active'
      limit 1
    `;
    const id = rows[0]?.id;
    const code = rows[0]?.code;
    if (typeof id !== "string" || typeof code !== "string") {
      throw new Error(
        `Trusted LifeMate source application is not registered: ${applicationCode}`,
      );
    }
    return { id, code };
  }

  async function listOwnerObservations(
    appUserId: string,
    fromDateValue: unknown,
    toDateValue: unknown,
  ): Promise<Record<string, unknown>[]> {
    const fromDate = requiredDate(fromDateValue, "fromDate");
    const toDate = requiredDate(toDateValue, "toDate");
    validateRange(fromDate, toDate, 3660);
    const { personId } = await resolveOwnerIdentity(sql, appUserId);

    const windowRows = await sql`
      select h.*, app.code as source_application_code
      from lifemate.health_observations h
      join ecosystem.applications app on app.id = h.source_application_id
      where h.person_id = ${personId}::uuid
        and h.observed_local_date between ${fromDate}::date and ${toDate}::date
      order by h.observed_at_utc desc, h.id desc
      limit 5000
    `;
    const latestRows = await sql`
      select h.*, app.code as source_application_code
      from lifemate.health_observations h
      join ecosystem.applications app on app.id = h.source_application_id
      join (
        select distinct on (observation_type) id
        from lifemate.health_observations
        where person_id = ${personId}::uuid
        order by observation_type, observed_at_utc desc, id desc
      ) latest on latest.id = h.id
      order by h.observed_at_utc desc, h.id desc
    `;

    const byId = new Map<string, Row>();
    for (const row of [...windowRows, ...latestRows]) {
      byId.set(String(row.id), row);
    }
    return [...byId.values()]
      .sort((a, b) => {
        const time = new Date(String(b.observed_at_utc)).getTime() -
          new Date(String(a.observed_at_utc)).getTime();
        if (time !== 0) return time;
        return String(b.id).localeCompare(String(a.id));
      })
      .map(mapObservation);
  }

  async function createOwnerObservation(
    appUserId: string,
    body: Record<string, unknown>,
    trustedApplicationCode = "wellmate",
  ): Promise<Record<string, unknown>> {
    const input = normalizeHealthObservationInput(body);

    return await sql.begin(async (tx: any) => {
      const { accountId, personId } = await resolveOwnerIdentity(
        tx,
        appUserId,
      );
      const sourceApplication = await resolveSourceApplication(
        tx,
        trustedApplicationCode,
      );
      const id = crypto.randomUUID();
      const inserted = await tx`
        insert into lifemate.health_observations
          (id, owner_user_id, person_id, recorded_by_account_id,
           source_application_id, client_request_id,
           observation_type, value_primary, value_secondary,
           unit_primary, unit_secondary, note, observed_at_utc,
           observed_local_date, time_zone, source_category,
           source_provider, source_external_id, metadata_json,
           version, created_at_utc, updated_at_utc)
        values
          (${id}::uuid, ${appUserId}::uuid, ${personId}::uuid,
           ${accountId}::uuid, ${sourceApplication.id}::uuid,
           ${input.clientRequestId}::uuid, ${input.observationType},
           ${input.valuePrimary}, ${input.valueSecondary},
           ${input.unitPrimary}, ${input.unitSecondary}, ${input.note},
           ${input.observedAtUtc}, ${input.observedLocalDate}::date,
           ${input.timeZone}, 'FirstPartyUserInput', ${sourceApplication.code},
           null, '{}'::jsonb, 1, now(), now())
        on conflict (person_id, source_application_id, client_request_id)
        do nothing
        returning *
      `;

      if (inserted[0]) {
        await tx`
          insert into lifemate.audit_logs
            (id, actor_user_id, action, resource_type, resource_id,
             metadata_json, created_at_utc)
          values
            (${crypto.randomUUID()}::uuid, ${appUserId}::uuid,
             'health.observation_created', 'health_observation', ${id}::uuid,
             ${
          JSON.stringify({
            observationType: input.observationType,
            sourceCategory: "FirstPartyUserInput",
            sourceApplicationCode: sourceApplication.code,
          })
        }::jsonb, now())
        `;
        return mapObservation({
          ...inserted[0],
          source_application_code: sourceApplication.code,
        });
      }

      const existing = await tx`
        select h.*, app.code as source_application_code
        from lifemate.health_observations h
        join ecosystem.applications app on app.id = h.source_application_id
        where h.person_id = ${personId}::uuid
          and h.source_application_id = ${sourceApplication.id}::uuid
          and h.client_request_id = ${input.clientRequestId}::uuid
        limit 1
      `;
      if (!existing[0]) {
        throw new ApiError(
          409,
          "health_observation_idempotency_conflict",
          "The health observation could not be resolved after a retry.",
        );
      }
      return mapObservation(existing[0]);
    });
  }

  async function deleteOwnerObservation(
    appUserId: string,
    observationIdValue: unknown,
  ): Promise<void> {
    const observationId = requiredUuid(observationIdValue, "observationId");
    await sql.begin(async (tx: any) => {
      const { accountId, personId } = await resolveOwnerIdentity(tx, appUserId);
      const deleted = await tx`
        delete from lifemate.health_observations
        where id = ${observationId}::uuid
          and person_id = ${personId}::uuid
          and recorded_by_account_id = ${accountId}::uuid
        returning id, observation_type
      `;
      if (!deleted[0]) {
        throw new ApiError(
          404,
          "health_observation_not_found",
          "Health observation was not found.",
        );
      }
      await tx`
        insert into lifemate.audit_logs
          (id, actor_user_id, action, resource_type, resource_id,
           metadata_json, created_at_utc)
        values
          (${crypto.randomUUID()}::uuid, ${appUserId}::uuid,
           'health.observation_deleted', 'health_observation',
           ${observationId}::uuid,
           ${
        JSON.stringify({
          observationType: String(deleted[0].observation_type),
        })
      }::jsonb, now())
      `;
    });
  }

  return {
    listOwnerObservations,
    createOwnerObservation,
    deleteOwnerObservation,
  };
}

function mapObservation(row: Row): Record<string, unknown> {
  return {
    id: row.id,
    personId: row.person_id,
    observationType: row.observation_type,
    valuePrimary: row.value_primary == null ? null : Number(row.value_primary),
    valueSecondary: row.value_secondary == null
      ? null
      : Number(row.value_secondary),
    unitPrimary: row.unit_primary,
    unitSecondary: row.unit_secondary,
    note: row.note,
    observedAtUtc: iso(row.observed_at_utc),
    observedLocalDate: dateString(row.observed_local_date),
    timeZone: row.time_zone,
    sourceCategory: row.source_category,
    sourceProvider: row.source_provider,
    sourceApplicationCode: row.source_application_code ?? null,
    version: Number(row.version),
    createdAtUtc: iso(row.created_at_utc),
    updatedAtUtc: iso(row.updated_at_utc),
  };
}

function iso(value: unknown): string {
  return value instanceof Date
    ? value.toISOString()
    : new Date(String(value)).toISOString();
}

function dateString(value: unknown): string {
  if (value instanceof Date) return value.toISOString().slice(0, 10);
  return String(value).slice(0, 10);
}

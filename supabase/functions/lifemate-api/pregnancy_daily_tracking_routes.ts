import { createCocoonIdentityResolver } from "./cocoon_identity.ts";
import { getLifeMateSql } from "./database_client.ts";
import { json } from "./http.ts";
import { requireMutationIdempotencyKey } from "./idempotency.ts";
import { createPregnancyAuthorization } from "./pregnancy_authorization.ts";
import { createPregnancyStore } from "./pregnancy_store.ts";
import {
  ApiError,
  readJsonObject,
  requiredDate,
  requiredTimeZone,
  requiredUuid,
  validateRange,
} from "./validation.ts";

type Row = Record<string, any>;

export const pregnancySymptomCatalog = [
  "nausea",
  "vomiting",
  "headache",
  "swelling",
  "cramps",
  "fatigue",
  "back_pain",
  "heavy_bleeding",
  "loss_of_consciousness",
  "severe_breathing_difficulty",
  "severe_chest_pain",
] as const;

export type PregnancySymptomCode = (typeof pregnancySymptomCatalog)[number];

const safetySignals: Partial<Record<PregnancySymptomCode, string>> = {
  heavy_bleeding: "heavy_bleeding",
  loss_of_consciousness: "loss_of_consciousness",
  severe_breathing_difficulty: "severe_breathing_difficulty",
  severe_chest_pain: "severe_chest_pain",
};

const safetyRuleSetVersion = 1;
const safetyReviewDueAtUtc = Date.parse("2027-03-04T00:00:00.000Z");

export type PregnancySafetyHandoff = {
  ruleSetVersion: number;
  outcome: "emergency" | "conservative_fallback";
  guidanceKey:
    | "pregnancy.safety.seek_emergency_care"
    | "pregnancy.safety.conservative_fallback";
  signal: string;
};

export function evaluatePregnancySymptomSafety(
  symptomCode: PregnancySymptomCode,
  atUtc: Date,
): PregnancySafetyHandoff | null {
  const signal = safetySignals[symptomCode];
  if (!signal) return null;
  if (atUtc.getTime() >= safetyReviewDueAtUtc) {
    return {
      ruleSetVersion: safetyRuleSetVersion,
      outcome: "conservative_fallback",
      guidanceKey: "pregnancy.safety.conservative_fallback",
      signal,
    };
  }
  return {
    ruleSetVersion: safetyRuleSetVersion,
    outcome: "emergency",
    guidanceKey: "pregnancy.safety.seek_emergency_care",
    signal,
  };
}

function requireSymptomCode(value: unknown): PregnancySymptomCode {
  const normalized = String(value ?? "").trim().toLowerCase();
  if (!(pregnancySymptomCatalog as readonly string[]).includes(normalized)) {
    throw new ApiError(
      400,
      "pregnancy_symptom_code_invalid",
      "Symptom code is not in the approved pregnancy catalog.",
    );
  }
  return normalized as PregnancySymptomCode;
}

function requireFeeling(value: unknown): "comfortable" | "mixed" | "difficult" {
  if (value === "comfortable" || value === "mixed" || value === "difficult") {
    return value;
  }
  throw new ApiError(
    400,
    "pregnancy_check_in_feeling_invalid",
    "Daily check-in feeling is invalid.",
  );
}

function requireEnergy(value: unknown): "low" | "steady" | "high" {
  if (value === "low" || value === "steady" || value === "high") return value;
  throw new ApiError(
    400,
    "pregnancy_check_in_energy_invalid",
    "Daily check-in energy is invalid.",
  );
}

function requireIntensity(value: unknown): "mild" | "moderate" | "strong" {
  if (value === "mild" || value === "moderate" || value === "strong") {
    return value;
  }
  throw new ApiError(
    400,
    "pregnancy_symptom_intensity_invalid",
    "Symptom intensity is invalid.",
  );
}

function optionalNote(value: unknown): string | null {
  if (value == null) return null;
  if (typeof value !== "string") {
    throw new ApiError(400, "pregnancy_symptom_note_invalid", "Note is invalid.");
  }
  const normalized = value.trim();
  if (!normalized) return null;
  if (normalized.length > 400) {
    throw new ApiError(
      400,
      "pregnancy_symptom_note_too_long",
      "Note must be 400 characters or fewer.",
    );
  }
  return normalized;
}

function requireUtcInstant(value: unknown): string {
  if (typeof value !== "string") {
    throw new ApiError(
      400,
      "pregnancy_observed_at_invalid",
      "A valid UTC observation instant is required.",
    );
  }
  const parsed = new Date(value);
  if (!value.endsWith("Z") || Number.isNaN(parsed.getTime())) {
    throw new ApiError(
      400,
      "pregnancy_observed_at_invalid",
      "A valid UTC observation instant is required.",
    );
  }
  return parsed.toISOString();
}

function requireMatchingIdempotencyKey(
  request: Request,
  clientRequestId: string,
): void {
  const key = requireMutationIdempotencyKey(request);
  if (key !== clientRequestId) {
    throw new ApiError(
      400,
      "pregnancy_idempotency_mismatch",
      "Idempotency-Key must match clientRequestId.",
    );
  }
}

function mapCheckIn(row: Row): Record<string, unknown> {
  return {
    id: String(row.id),
    episodeId: String(row.episode_id),
    loggedLocalDate: String(row.logged_local_date).slice(0, 10),
    timeZone: String(row.time_zone),
    feeling: String(row.feeling),
    energy: String(row.energy),
    clientRequestId: String(row.client_request_id),
    version: Number(row.version),
    createdAtUtc: new Date(row.created_at_utc).toISOString(),
  };
}

function mapSymptom(row: Row): Record<string, unknown> {
  const signal = row.safety_signal == null ? null : String(row.safety_signal);
  const ruleSetVersion = row.safety_rule_set_version == null
    ? null
    : Number(row.safety_rule_set_version);
  return {
    id: String(row.id),
    episodeId: String(row.episode_id),
    symptomCode: String(row.symptom_code),
    intensity: String(row.intensity),
    note: row.note == null ? null : String(row.note),
    observedAtUtc: new Date(row.observed_at_utc).toISOString(),
    observedLocalDate: String(row.observed_local_date).slice(0, 10),
    timeZone: String(row.time_zone),
    clientRequestId: String(row.client_request_id),
    version: Number(row.version),
    createdAtUtc: new Date(row.created_at_utc).toISOString(),
    safetyHandoff: signal == null || ruleSetVersion == null
      ? null
      : {
        ruleSetVersion,
        signal,
        outcome: new Date().getTime() >= safetyReviewDueAtUtc
          ? "conservative_fallback"
          : "emergency",
        guidanceKey: new Date().getTime() >= safetyReviewDueAtUtc
          ? "pregnancy.safety.conservative_fallback"
          : "pregnancy.safety.seek_emergency_care",
      },
  };
}

export function createPregnancyDailyTrackingRouteHandler(databaseUrl: string) {
  const sql = getLifeMateSql(databaseUrl);
  const identity = createCocoonIdentityResolver(databaseUrl);
  const pregnancy = createPregnancyStore(databaseUrl);
  const authorization = createPregnancyAuthorization(databaseUrl);

  async function activeContext(appUserId: string) {
    const { accountId, personId } = await identity.resolve(appUserId);
    const episode = await pregnancy.getCurrentEpisode(personId);
    if (!episode) {
      throw new ApiError(
        409,
        "pregnancy_active_episode_required",
        "An active pregnancy episode is required.",
      );
    }
    return { accountId, personId, episode };
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
      path === "/api/v1/cocoon/pregnancy/symptom-catalog"
    ) {
      const { accountId, personId, episode } = await activeContext(appUserId);
      await authorization.requireAccess({
        callerAccountId: accountId,
        subjectPersonId: personId,
        episodeId: episode.id,
        scope: "pregnancy.observations.read",
      });
      return json({
        contractVersion: 1,
        catalogVersion: 1,
        symptomCodes: pregnancySymptomCatalog,
      });
    }

    if (
      request.method === "GET" &&
      path === "/api/v1/cocoon/pregnancy/daily-tracking"
    ) {
      const { accountId, personId, episode } = await activeContext(appUserId);
      await authorization.requireAccess({
        callerAccountId: accountId,
        subjectPersonId: personId,
        episodeId: episode.id,
        scope: "pregnancy.observations.read",
      });
      const url = new URL(request.url);
      const fromDate = requiredDate(url.searchParams.get("fromDate"), "fromDate");
      const toDate = requiredDate(url.searchParams.get("toDate"), "toDate");
      validateRange(fromDate, toDate, 31);
      const [checkIns, symptoms] = await Promise.all([
        sql`
          select * from pregnancy.daily_check_ins
          where episode_id=${episode.id}::uuid
            and logged_local_date between ${fromDate}::date and ${toDate}::date
          order by logged_local_date desc, created_at_utc desc, id desc
          limit 64
        `,
        sql`
          select * from pregnancy.symptom_entries
          where episode_id=${episode.id}::uuid
            and observed_local_date between ${fromDate}::date and ${toDate}::date
          order by observed_at_utc desc, id desc
          limit 256
        `,
      ]);
      return json({
        contractVersion: 1,
        episodeId: episode.id,
        checkIns: checkIns.map(mapCheckIn),
        symptoms: symptoms.map(mapSymptom),
      });
    }

    if (
      request.method === "POST" &&
      path === "/api/v1/cocoon/pregnancy/check-ins"
    ) {
      const { accountId, personId, episode } = await activeContext(appUserId);
      await authorization.requireAccess({
        callerAccountId: accountId,
        subjectPersonId: personId,
        episodeId: episode.id,
        scope: "pregnancy.owner.manage",
      });
      const body = await readJsonObject(request);
      const clientRequestId = requiredUuid(body.clientRequestId, "clientRequestId");
      requireMatchingIdempotencyKey(request, clientRequestId);
      const loggedLocalDate = requiredDate(body.loggedLocalDate, "loggedLocalDate");
      const timeZone = requiredTimeZone(body.timeZone);
      const feeling = requireFeeling(body.feeling);
      const energy = requireEnergy(body.energy);

      const result = await sql.begin(async (tx: any) => {
        const prior = await tx`
          select * from pregnancy.daily_check_ins
          where episode_id=${episode.id}::uuid
            and client_request_id=${clientRequestId}::uuid
          limit 1
        `;
        if (prior[0]) {
          if (
            String(prior[0].logged_local_date).slice(0, 10) !== loggedLocalDate ||
            String(prior[0].time_zone) !== timeZone ||
            String(prior[0].feeling) !== feeling ||
            String(prior[0].energy) !== energy
          ) {
            throw new ApiError(
              409,
              "idempotency_key_reused",
              "clientRequestId was already used for a different check-in.",
            );
          }
          return { row: prior[0], created: false };
        }
        const sameDay = await tx`
          select * from pregnancy.daily_check_ins
          where episode_id=${episode.id}::uuid
            and logged_local_date=${loggedLocalDate}::date
          limit 1
          for update
        `;
        if (sameDay[0]) {
          throw new ApiError(
            409,
            "pregnancy_daily_check_in_exists",
            "A daily check-in already exists for this local date.",
          );
        }
        const rows = await tx`
          insert into pregnancy.daily_check_ins(
            episode_id,logged_local_date,time_zone,feeling,energy,
            client_request_id,recorded_by_account_id
          ) values (
            ${episode.id}::uuid,${loggedLocalDate}::date,${timeZone},${feeling},
            ${energy},${clientRequestId}::uuid,${accountId}::uuid
          ) returning *
        `;
        return { row: rows[0], created: true };
      });
      return json(
        { contractVersion: 1, checkIn: mapCheckIn(result.row) },
        result.created ? 201 : 200,
      );
    }

    if (
      request.method === "POST" &&
      path === "/api/v1/cocoon/pregnancy/symptoms"
    ) {
      const { accountId, personId, episode } = await activeContext(appUserId);
      await authorization.requireAccess({
        callerAccountId: accountId,
        subjectPersonId: personId,
        episodeId: episode.id,
        scope: "pregnancy.owner.manage",
      });
      const body = await readJsonObject(request);
      const clientRequestId = requiredUuid(body.clientRequestId, "clientRequestId");
      requireMatchingIdempotencyKey(request, clientRequestId);
      const symptomCode = requireSymptomCode(body.symptomCode);
      const intensity = requireIntensity(body.intensity);
      const note = optionalNote(body.note);
      const observedAtUtc = requireUtcInstant(body.observedAtUtc);
      const observedLocalDate = requiredDate(
        body.observedLocalDate,
        "observedLocalDate",
      );
      const timeZone = requiredTimeZone(body.timeZone);
      const safetyHandoff = evaluatePregnancySymptomSafety(
        symptomCode,
        new Date(),
      );

      const result = await sql.begin(async (tx: any) => {
        const prior = await tx`
          select * from pregnancy.symptom_entries
          where episode_id=${episode.id}::uuid
            and client_request_id=${clientRequestId}::uuid
          limit 1
        `;
        if (prior[0]) {
          if (
            String(prior[0].symptom_code) !== symptomCode ||
            String(prior[0].intensity) !== intensity ||
            (prior[0].note == null ? null : String(prior[0].note)) !== note ||
            new Date(prior[0].observed_at_utc).toISOString() !== observedAtUtc ||
            String(prior[0].observed_local_date).slice(0, 10) !== observedLocalDate ||
            String(prior[0].time_zone) !== timeZone
          ) {
            throw new ApiError(
              409,
              "idempotency_key_reused",
              "clientRequestId was already used for a different symptom entry.",
            );
          }
          return { row: prior[0], created: false };
        }
        const rows = await tx`
          insert into pregnancy.symptom_entries(
            episode_id,symptom_code,intensity,note,observed_at_utc,
            observed_local_date,time_zone,safety_signal,safety_rule_set_version,
            client_request_id,recorded_by_account_id
          ) values (
            ${episode.id}::uuid,${symptomCode},${intensity},${note},
            ${observedAtUtc}::timestamptz,${observedLocalDate}::date,${timeZone},
            ${safetyHandoff?.signal ?? null},
            ${safetyHandoff?.ruleSetVersion ?? null},
            ${clientRequestId}::uuid,${accountId}::uuid
          ) returning *
        `;
        return { row: rows[0], created: true };
      });

      return json(
        {
          contractVersion: 1,
          symptom: mapSymptom(result.row),
          safetyHandoff,
        },
        result.created ? 201 : 200,
      );
    }

    return null;
  };
}

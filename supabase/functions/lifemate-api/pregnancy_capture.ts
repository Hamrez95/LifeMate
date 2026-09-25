import { createCocoonIdentityResolver } from "./cocoon_identity.ts";
import { getLifeMateSql } from "./database_client.ts";
import { json } from "./http.ts";
import { createPregnancyAuthorization } from "./pregnancy_authorization.ts";
import { createPregnancyStore } from "./pregnancy_store.ts";
import {
  ApiError,
  limitedOptional,
  readJsonObject,
  requiredDate,
  requiredTimestamp,
  requiredTimeZone,
  requiredUuid,
  validateRange,
  validateReportedAt,
} from "./validation.ts";

type CaptureContext = {
  accountId: string;
  personId: string;
  episodeId: string;
};

type Row = Record<string, any>;

type SymptomCatalogEntry = {
  code: string;
  label: string;
  sortOrder: number;
};

function localDateFor(timestamp: Date, timeZone: string): string {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(timestamp);
  const values = Object.fromEntries(
    parts.map((part) => [part.type, part.value]),
  );
  return `${values.year}-${values.month}-${values.day}`;
}

function requireObservedContext(body: Record<string, unknown>) {
  const observedAt = requiredTimestamp(body.observedAtUtc, "observedAtUtc");
  validateReportedAt(observedAt);
  const timeZone = requiredTimeZone(body.timeZone);
  const localDate = requiredDate(body.localDate, "localDate");
  if (localDateFor(observedAt, timeZone) !== localDate) {
    throw new ApiError(
      400,
      "capture_local_date_mismatch",
      "localDate must match observedAtUtc in the supplied timeZone.",
    );
  }
  return { observedAt, timeZone, localDate };
}

function oneOf<T extends string>(
  value: unknown,
  field: string,
  allowed: readonly T[],
): T {
  const normalized = String(value ?? "").trim().toLowerCase();
  if (!allowed.includes(normalized as T)) {
    throw new ApiError(400, `invalid_${field}`, `${field} is invalid.`);
  }
  return normalized as T;
}

export function normalizePregnancyFeeling(value: unknown) {
  return oneOf(
    value,
    "feeling",
    ["comfortable", "mixed", "difficult"] as const,
  );
}

export function normalizePregnancyEnergy(value: unknown) {
  return oneOf(value, "energy", ["low", "steady", "high"] as const);
}

export function normalizePregnancySymptomIntensity(value: unknown) {
  return oneOf(value, "intensity", ["mild", "moderate", "strong"] as const);
}

export function normalizePregnancyMood(value: unknown) {
  return oneOf(
    value,
    "moodCode",
    [
      "very_low",
      "low",
      "neutral",
      "good",
      "very_good",
    ] as const,
  );
}

export function normalizePregnancySymptomCode(value: unknown): string {
  const code = String(value ?? "").trim().toLowerCase();
  if (!/^[a-z0-9][a-z0-9._-]{1,63}$/.test(code)) {
    throw new ApiError(
      400,
      "invalid_symptomCode",
      "symptomCode must be a stable structured catalog code.",
    );
  }
  return code;
}

export function requiredCatalogVersion(value: unknown): string {
  const version = String(value ?? "").trim();
  if (version.length < 1 || version.length > 64) {
    throw new ApiError(
      400,
      "pregnancy_symptom_catalog_version_invalid",
      "A reviewed symptom catalog version is required.",
    );
  }
  return version;
}

export function requestedCatalogLocale(request: Request): "en" | "fa" {
  const locale = (new URL(request.url).searchParams.get("locale") ?? "en")
    .trim().toLowerCase();
  if (locale === "en" || locale === "fa") return locale;
  throw new ApiError(
    400,
    "pregnancy_symptom_catalog_locale_invalid",
    "A supported catalog locale is required.",
  );
}

function captureRow(row: Row) {
  return {
    id: String(row.id),
    episodeId: String(row.episode_id),
    observedAtUtc: new Date(row.observed_at_utc).toISOString(),
    localDate: captureLocalDate(row.local_date),
    timeZone: String(row.time_zone),
    feeling: row.feeling ?? undefined,
    energy: row.energy ?? undefined,
    symptomCode: row.symptom_code ?? undefined,
    intensity: row.intensity ?? undefined,
    note: row.note ?? undefined,
    moodCode: row.mood_code ?? undefined,
    version: Number(row.version),
    createdAtUtc: new Date(row.created_at_utc).toISOString(),
    updatedAtUtc: new Date(row.updated_at_utc).toISOString(),
  };
}

function captureLocalDate(value: unknown): string {
  return value instanceof Date
    ? value.toISOString().slice(0, 10)
    : String(value).slice(0, 10);
}

function sameCaptureReplayContext(
  row: Row,
  context: CaptureContext,
  observed: { observedAt: Date; timeZone: string; localDate: string },
): boolean {
  return String(row.episode_id) === context.episodeId &&
    new Date(row.observed_at_utc).toISOString() ===
      observed.observedAt.toISOString() &&
    captureLocalDate(row.local_date) === observed.localDate &&
    String(row.time_zone) === observed.timeZone;
}

function normalizedStoredNote(value: unknown): string | null {
  return value == null ? null : String(value);
}

function idempotencyReuse(message: string): never {
  throw new ApiError(409, "idempotency_key_reused", message);
}

export function createPregnancyCaptureRouteHandler(databaseUrl: string) {
  const sql = getLifeMateSql(databaseUrl);
  const identity = createCocoonIdentityResolver(databaseUrl);
  const pregnancy = createPregnancyStore(databaseUrl);
  const authorization = createPregnancyAuthorization(databaseUrl);

  async function ownerContext(appUserId: string): Promise<CaptureContext> {
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
      scope: "pregnancy.owner.manage",
    });
    return { accountId, personId, episodeId: episode.id };
  }

  async function createCheckIn(
    appUserId: string,
    body: Record<string, unknown>,
  ) {
    const context = await ownerContext(appUserId);
    const requestId = requiredUuid(body.clientRequestId, "clientRequestId");
    const observed = requireObservedContext(body);
    const feeling = normalizePregnancyFeeling(body.feeling);
    const energy = normalizePregnancyEnergy(body.energy);

    return await sql.begin(async (tx: any) => {
      await tx`select pg_advisory_xact_lock(hashtextextended(${`${context.episodeId}:${observed.localDate}`}::text, 0))`;
      const prior = await tx`
        select * from pregnancy.daily_check_ins
        where mother_person_id=${context.personId}::uuid
          and client_request_id=${requestId}::uuid
        limit 1
      `;
      if (prior[0]) {
        if (
          !sameCaptureReplayContext(prior[0], context, observed) ||
          String(prior[0].feeling) !== feeling ||
          String(prior[0].energy) !== energy
        ) {
          idempotencyReuse(
            "clientRequestId was already used for a different daily check-in.",
          );
        }
        return captureRow(prior[0]);
      }

      const existing = await tx`
        select id from pregnancy.daily_check_ins
        where episode_id=${context.episodeId}::uuid
          and local_date=${observed.localDate}::date
        limit 1
      `;
      if (existing[0]) {
        throw new ApiError(
          409,
          "daily_check_in_exists",
          "A daily check-in already exists for this local date.",
        );
      }

      const rows = await tx`
        insert into pregnancy.daily_check_ins(
          episode_id,mother_person_id,observed_at_utc,local_date,time_zone,
          feeling,energy,client_request_id,recorded_by_account_id
        ) values (
          ${context.episodeId}::uuid,${context.personId}::uuid,
          ${observed.observedAt},${observed.localDate}::date,${observed.timeZone},
          ${feeling},${energy},${requestId}::uuid,${context.accountId}::uuid
        ) returning *
      `;
      return captureRow(rows[0]);
    });
  }

  async function createSymptom(
    appUserId: string,
    body: Record<string, unknown>,
  ) {
    const context = await ownerContext(appUserId);
    const requestId = requiredUuid(body.clientRequestId, "clientRequestId");
    const observed = requireObservedContext(body);
    const symptomCode = normalizePregnancySymptomCode(body.symptomCode);
    const catalogVersion = requiredCatalogVersion(body.catalogVersion);
    const intensity = normalizePregnancySymptomIntensity(body.intensity);
    const note = limitedOptional(body.note, "note", 400);

    const approved = await sql`
      select 1
      from pregnancy.symptom_catalog_releases release
      join pregnancy.symptom_catalog_entries entry on entry.release_id=release.id
      where release.status='published'
        and release.version=${catalogVersion}
        and entry.code=${symptomCode}
      limit 1
    `;
    if (!approved[0]) {
      throw new ApiError(
        409,
        "pregnancy_symptom_catalog_unavailable",
        "This symptom is not available in the current reviewed catalog.",
      );
    }

    return await sql.begin(async (tx: any) => {
      await tx`select pg_advisory_xact_lock(hashtextextended(${`${context.personId}:${requestId}`}::text, 0))`;
      const prior = await tx`
        select * from pregnancy.symptom_reports
        where mother_person_id=${context.personId}::uuid
          and client_request_id=${requestId}::uuid
        limit 1
      `;
      if (prior[0]) {
        if (
          !sameCaptureReplayContext(prior[0], context, observed) ||
          String(prior[0].symptom_code) !== symptomCode ||
          String(prior[0].intensity) !== intensity ||
          normalizedStoredNote(prior[0].note) !== note
        ) {
          idempotencyReuse(
            "clientRequestId was already used for a different symptom report.",
          );
        }
        return captureRow(prior[0]);
      }
      const rows = await tx`
        insert into pregnancy.symptom_reports(
          episode_id,mother_person_id,observed_at_utc,local_date,time_zone,
          symptom_code,intensity,note,client_request_id,recorded_by_account_id
        ) values (
          ${context.episodeId}::uuid,${context.personId}::uuid,
          ${observed.observedAt},${observed.localDate}::date,${observed.timeZone},
          ${symptomCode},${intensity},${note},${requestId}::uuid,
          ${context.accountId}::uuid
        ) returning *
      `;
      return captureRow(rows[0]);
    });
  }

  async function createMood(appUserId: string, body: Record<string, unknown>) {
    const context = await ownerContext(appUserId);
    const requestId = requiredUuid(body.clientRequestId, "clientRequestId");
    const observed = requireObservedContext(body);
    const moodCode = normalizePregnancyMood(body.moodCode);

    return await sql.begin(async (tx: any) => {
      await tx`select pg_advisory_xact_lock(hashtextextended(${`${context.personId}:${requestId}`}::text, 0))`;
      const prior = await tx`
        select * from pregnancy.mood_entries
        where mother_person_id=${context.personId}::uuid
          and client_request_id=${requestId}::uuid
        limit 1
      `;
      if (prior[0]) {
        if (
          !sameCaptureReplayContext(prior[0], context, observed) ||
          String(prior[0].mood_code) !== moodCode
        ) {
          idempotencyReuse(
            "clientRequestId was already used for a different mood entry.",
          );
        }
        return captureRow(prior[0]);
      }
      const rows = await tx`
        insert into pregnancy.mood_entries(
          episode_id,mother_person_id,observed_at_utc,local_date,time_zone,
          mood_code,client_request_id,recorded_by_account_id
        ) values (
          ${context.episodeId}::uuid,${context.personId}::uuid,
          ${observed.observedAt},${observed.localDate}::date,${observed.timeZone},
          ${moodCode},${requestId}::uuid,${context.accountId}::uuid
        ) returning *
      `;
      return captureRow(rows[0]);
    });
  }

  async function listCaptures(
    appUserId: string,
    fromDate: string,
    toDate: string,
  ) {
    const context = await ownerContext(appUserId);
    const [checkIns, symptoms, moods] = await Promise.all([
      sql`select * from pregnancy.daily_check_ins where episode_id=${context.episodeId}::uuid and local_date between ${fromDate}::date and ${toDate}::date order by observed_at_utc desc,id desc`,
      sql`select * from pregnancy.symptom_reports where episode_id=${context.episodeId}::uuid and local_date between ${fromDate}::date and ${toDate}::date order by observed_at_utc desc,id desc`,
      sql`select * from pregnancy.mood_entries where episode_id=${context.episodeId}::uuid and local_date between ${fromDate}::date and ${toDate}::date order by observed_at_utc desc,id desc`,
    ]);
    return {
      contractVersion: 1,
      episodeId: context.episodeId,
      checkIns: checkIns.map(captureRow),
      symptoms: symptoms.map(captureRow),
      moods: moods.map(captureRow),
    };
  }

  async function symptomCatalog(appUserId: string, locale: "en" | "fa") {
    await ownerContext(appUserId);
    const releases = await sql`
      select id,version
      from pregnancy.symptom_catalog_releases
      where status='published'
      limit 1
    `;
    const release = releases[0];
    if (!release) {
      return {
        contractVersion: 1,
        version: "unpublished",
        locale,
        entries: [],
      };
    }
    const rows = await sql`
      select code,display_label,sort_order
      from pregnancy.symptom_catalog_entries
      where release_id=${String(release.id)}::uuid and locale=${locale}
      order by sort_order asc,code asc
    `;
    const entries: SymptomCatalogEntry[] = rows.map((row: Row) => ({
      code: String(row.code),
      label: String(row.display_label),
      sortOrder: Number(row.sort_order),
    }));
    return {
      contractVersion: 1,
      version: String(release.version),
      locale,
      entries,
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
      request.method === "POST" && path === "/api/v1/cocoon/pregnancy/check-ins"
    ) {
      return json({
        contractVersion: 1,
        checkIn: await createCheckIn(appUserId, await readJsonObject(request)),
      }, 201);
    }
    if (
      request.method === "POST" && path === "/api/v1/cocoon/pregnancy/symptoms"
    ) {
      return json({
        contractVersion: 1,
        symptom: await createSymptom(appUserId, await readJsonObject(request)),
      }, 201);
    }
    if (
      request.method === "POST" && path === "/api/v1/cocoon/pregnancy/moods"
    ) {
      return json({
        contractVersion: 1,
        mood: await createMood(appUserId, await readJsonObject(request)),
      }, 201);
    }
    if (
      request.method === "GET" &&
      path === "/api/v1/cocoon/pregnancy/symptom-catalog"
    ) {
      return json(
        await symptomCatalog(appUserId, requestedCatalogLocale(request)),
      );
    }
    if (
      request.method === "GET" &&
      path === "/api/v1/cocoon/pregnancy/daily-captures"
    ) {
      const url = new URL(request.url);
      const fromDate = requiredDate(
        url.searchParams.get("fromDate"),
        "fromDate",
      );
      const toDate = requiredDate(url.searchParams.get("toDate"), "toDate");
      validateRange(fromDate, toDate, 31);
      return json(await listCaptures(appUserId, fromDate, toDate));
    }
    return null;
  };
}

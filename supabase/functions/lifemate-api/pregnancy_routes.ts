import { getLifeMateSql } from "./database_client.ts";
import { json } from "./http.ts";
import { requireMutationIdempotencyKey } from "./idempotency.ts";
import {
  createPregnancyAuthorization,
  type PregnancyScope,
} from "./pregnancy_authorization.ts";
import {
  deriveGestationalAge,
  PregnancyDatingError,
  type PregnancyDatingMethod,
} from "./pregnancy_dating.ts";
import {
  createPregnancyStore,
  type PregnancyEpisode,
  type PregnancyOutcome,
  PregnancyStoreError,
} from "./pregnancy_store.ts";
import { ApiError, readJsonObject } from "./validation.ts";

type Row = Record<string, unknown>;

type PregnancyEnrollmentState =
  | "not_enrolled"
  | "draft"
  | "active"
  | "ended";

type PregnancyEntitlementState =
  | "active"
  | "inactive"
  | "unknown";

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const isoDatePattern = /^\d{4}-\d{2}-\d{2}$/;

function requiredUuid(value: unknown, code: string): string {
  if (typeof value !== "string" || !uuidPattern.test(value)) {
    throw new ApiError(400, code, "A valid identifier is required.");
  }
  return value;
}

function requiredInteger(value: unknown, code: string): number {
  if (!Number.isInteger(value) || Number(value) < 1) {
    throw new ApiError(400, code, "A valid version is required.");
  }
  return Number(value);
}

function optionalIsoDate(value: unknown, code: string): string | null {
  if (value == null) return null;
  if (typeof value !== "string" || !isoDatePattern.test(value)) {
    throw new ApiError(400, code, "A valid ISO date is required.");
  }
  return value;
}

function requiredAsOfDate(request: Request): string {
  const value = new URL(request.url).searchParams.get("asOfDate");
  if (!value || !isoDatePattern.test(value)) {
    throw new ApiError(
      400,
      "pregnancy_as_of_date_required",
      "A local asOfDate in YYYY-MM-DD format is required.",
    );
  }
  return value;
}

function requireDatingMethod(value: unknown): PregnancyDatingMethod {
  const supported: PregnancyDatingMethod[] = [
    "lmp",
    "edd",
    "clinician_ultrasound",
    "manual_correction",
    "imported",
  ];
  if (
    typeof value !== "string" ||
    !supported.includes(value as PregnancyDatingMethod)
  ) {
    throw new ApiError(
      400,
      "pregnancy_dating_method_invalid",
      "Pregnancy dating method is invalid.",
    );
  }
  return value as PregnancyDatingMethod;
}

function optionalDatingMethod(value: unknown): PregnancyDatingMethod | null {
  return value == null ? null : requireDatingMethod(value);
}

function requireOutcome(value: unknown): PregnancyOutcome {
  const supported: PregnancyOutcome[] = [
    "delivered",
    "pregnancy_loss",
    "other",
    "unknown",
  ];
  if (
    typeof value !== "string" || !supported.includes(value as PregnancyOutcome)
  ) {
    throw new ApiError(
      400,
      "pregnancy_outcome_invalid",
      "Pregnancy outcome is invalid.",
    );
  }
  return value as PregnancyOutcome;
}

function normalizeReferenceDays(value: unknown): number | null {
  if (value == null) return null;
  if (!Number.isInteger(value) || Number(value) < 0 || Number(value) > 308) {
    throw new ApiError(
      400,
      "pregnancy_reference_days_invalid",
      "Gestational age at reference is invalid.",
    );
  }
  return Number(value);
}

export function mapPregnancyStoreError(error: unknown): never {
  if (error instanceof PregnancyDatingError) {
    throw new ApiError(400, error.message, "Pregnancy dating data is invalid.");
  }
  if (!(error instanceof PregnancyStoreError)) throw error;
  switch (error.code) {
    case "idempotency_key_invalid":
      throw new ApiError(400, error.code, "Idempotency key is invalid.");
    case "pregnancy_not_found":
      throw new ApiError(404, error.code, "Pregnancy episode was not found.");
    case "active_pregnancy_exists":
    case "pregnancy_version_conflict":
    case "pregnancy_not_draft":
    case "pregnancy_ended":
    case "pregnancy_already_ended":
      throw new ApiError(409, error.code, "Pregnancy state has changed.");
    default:
      throw new ApiError(
        500,
        "pregnancy_operation_failed",
        "Pregnancy request could not be completed.",
      );
  }
}

export function pregnancyEpisodeReadModel(
  episode: PregnancyEpisode,
  asOfDate: string | null,
): Row {
  let gestationalAge = null;
  if (asOfDate != null) {
    gestationalAge = deriveGestationalAge(
      {
        method: episode.datingMethod,
        lmpDate: episode.lmpDate,
        estimatedDueDate: episode.estimatedDueDate,
        referenceDate: episode.datingReferenceDate,
        gestationalAgeAtReferenceDays: episode.gestationalAgeAtReferenceDays,
      },
      asOfDate,
    );
  }
  return {
    id: episode.id,
    motherPersonId: episode.motherPersonId,
    status: episode.status,
    dating: {
      method: episode.datingMethod,
      lmpDate: episode.lmpDate,
      estimatedDueDate: episode.estimatedDueDate,
      referenceDate: episode.datingReferenceDate,
      gestationalAgeAtReferenceDays: episode.gestationalAgeAtReferenceDays,
      gestationalAge,
    },
    outcome: episode.outcome,
    activatedAtUtc: episode.activatedAtUtc,
    endedAtUtc: episode.endedAtUtc,
    version: episode.version,
    updatedAtUtc: episode.updatedAtUtc,
  };
}

export function createPregnancyRouteHandler(databaseUrl: string) {
  const sql = getLifeMateSql(databaseUrl);
  const store = createPregnancyStore(databaseUrl);
  const authorization = createPregnancyAuthorization(databaseUrl);

  async function selfPersonId(accountId: string): Promise<string> {
    const rows = await sql`
      select person_id
      from core.account_person_links
      where account_id=${accountId}::uuid
        and link_type='Self'
        and status='Active'
      order by created_at_utc asc
      limit 1
    `;
    if (!rows[0]?.person_id) {
      throw new ApiError(
        409,
        "cocoon_person_context_missing",
        "Cocoon person context is not ready.",
      );
    }
    return String(rows[0].person_id);
  }

  async function requireAccess(
    accountId: string,
    personId: string,
    episodeId: string | null,
    scope: PregnancyScope,
  ): Promise<void> {
    await authorization.requireAccess({
      callerAccountId: accountId,
      subjectPersonId: personId,
      episodeId,
      scope,
    });
  }

  async function entitlementState(accountId: string): Promise<Row> {
    try {
      const rows = await sql`
        select s.id,s.status,s.current_period_end_utc
        from commerce.subscriptions s
        join commerce.products p on p.id=s.product_id
        where s.owner_account_id=${accountId}::uuid
          and p.code='cocoonmate'
        order by s.updated_at_utc desc,s.id desc
        limit 1
      `;
      if (!rows[0]) {
        return {
          state: "inactive" satisfies PregnancyEntitlementState,
          reference: null,
        };
      }
      const status = String(rows[0].status ?? "").toLowerCase();
      const active = status === "active" || status === "trialing";
      return {
        state:
          (active ? "active" : "inactive") satisfies PregnancyEntitlementState,
        reference: String(rows[0].id),
        currentPeriodEndUtc: rows[0].current_period_end_utc == null
          ? null
          : new Date(String(rows[0].current_period_end_utc)).toISOString(),
      };
    } catch {
      return {
        state: "unknown" satisfies PregnancyEntitlementState,
        reference: null,
      };
    }
  }

  function enrollmentState(
    current: PregnancyEpisode | null,
    history: PregnancyEpisode[],
  ): PregnancyEnrollmentState {
    if (current) return "active";
    if (history.some((episode) => episode.status === "draft")) return "draft";
    if (history.some((episode) => episode.status === "ended")) return "ended";
    return "not_enrolled";
  }

  async function bootstrap(
    request: Request,
    accountId: string,
  ): Promise<Response> {
    const asOfDate = requiredAsOfDate(request);
    const personId = await selfPersonId(accountId);
    await requireAccess(accountId, personId, null, "pregnancy.summary.read");
    const [current, history, entitlement] = await Promise.all([
      store.getCurrentEpisode(personId),
      store.listHistory(personId),
      entitlementState(accountId),
    ]);
    return json({
      contractVersion: 1,
      subject: { personId },
      enrollmentState: enrollmentState(current, history),
      entitlementState: entitlement,
      activeEpisode: current == null
        ? null
        : pregnancyEpisodeReadModel(current, asOfDate),
      runtime: {
        serverAuthoritativeSharing: true,
        serverAuthoritativeEntitlementActivation: true,
        cachedOwnerSnapshotAllowed: true,
        cachedSharedSnapshotAllowed: false,
      },
    });
  }

  async function currentSnapshot(
    request: Request,
    accountId: string,
  ): Promise<Response> {
    const asOfDate = requiredAsOfDate(request);
    const personId = await selfPersonId(accountId);
    const current = await store.getCurrentEpisode(personId);
    if (!current) return json({ contractVersion: 1, episode: null });
    await requireAccess(
      accountId,
      personId,
      current.id,
      "pregnancy.summary.read",
    );
    return json({
      contractVersion: 1,
      episode: pregnancyEpisodeReadModel(current, asOfDate),
      todayActions: [],
      nextAppointment: null,
      content: { version: null, references: [] },
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
    try {
      if (request.method === "GET" && path === "/api/v1/cocoon/bootstrap") {
        return await bootstrap(request, appUserId);
      }
      if (
        request.method === "GET" && path === "/api/v1/cocoon/pregnancy/snapshot"
      ) {
        return await currentSnapshot(request, appUserId);
      }

      const personId = await selfPersonId(appUserId);

      if (
        request.method === "GET" && path === "/api/v1/cocoon/pregnancy/episodes"
      ) {
        await requireAccess(
          appUserId,
          personId,
          null,
          "pregnancy.summary.read",
        );
        const asOfDate = new URL(request.url).searchParams.get("asOfDate");
        if (asOfDate != null && !isoDatePattern.test(asOfDate)) {
          throw new ApiError(
            400,
            "pregnancy_as_of_date_invalid",
            "asOfDate is invalid.",
          );
        }
        const history = await store.listHistory(personId);
        return json({
          contractVersion: 1,
          episodes: history.map((episode) =>
            pregnancyEpisodeReadModel(episode, asOfDate)
          ),
        });
      }

      if (
        request.method === "POST" &&
        path === "/api/v1/cocoon/pregnancy/episodes"
      ) {
        await requireAccess(
          appUserId,
          personId,
          null,
          "pregnancy.owner.manage",
        );
        const body = await readJsonObject(request);
        const status = body.status === "draft" || body.status === "active"
          ? body.status
          : null;
        if (!status) {
          throw new ApiError(
            400,
            "pregnancy_status_invalid",
            "Pregnancy status is invalid.",
          );
        }
        const created = await store.createEpisode({
          motherPersonId: personId,
          status,
          method: optionalDatingMethod(body.method),
          lmpDate: optionalIsoDate(body.lmpDate, "pregnancy_lmp_invalid"),
          estimatedDueDate: optionalIsoDate(
            body.estimatedDueDate,
            "pregnancy_edd_invalid",
          ),
          referenceDate: optionalIsoDate(
            body.referenceDate,
            "pregnancy_reference_date_invalid",
          ),
          gestationalAgeAtReferenceDays: normalizeReferenceDays(
            body.gestationalAgeAtReferenceDays,
          ),
          idempotencyKey: requireMutationIdempotencyKey(request),
          actorAccountId: appUserId,
        });
        return json({
          contractVersion: 1,
          episode: pregnancyEpisodeReadModel(created, null),
        }, 201);
      }

      const activateMatch = path.match(
        /^\/api\/v1\/cocoon\/pregnancy\/episodes\/([0-9a-f-]{36})\/activate$/i,
      );
      if (request.method === "POST" && activateMatch) {
        const episodeId = requiredUuid(
          activateMatch[1],
          "pregnancy_episode_id_invalid",
        );
        await requireAccess(
          appUserId,
          personId,
          episodeId,
          "pregnancy.owner.manage",
        );
        const body = await readJsonObject(request);
        const episode = await store.activateEpisode({
          motherPersonId: personId,
          episodeId,
          expectedVersion: requiredInteger(
            body.expectedVersion,
            "pregnancy_version_invalid",
          ),
          idempotencyKey: requireMutationIdempotencyKey(request),
          actorAccountId: appUserId,
        });
        return json({
          contractVersion: 1,
          episode: pregnancyEpisodeReadModel(episode, null),
        });
      }

      const datingMatch = path.match(
        /^\/api\/v1\/cocoon\/pregnancy\/episodes\/([0-9a-f-]{36})\/dating$/i,
      );
      if (request.method === "PATCH" && datingMatch) {
        const episodeId = requiredUuid(
          datingMatch[1],
          "pregnancy_episode_id_invalid",
        );
        await requireAccess(
          appUserId,
          personId,
          episodeId,
          "pregnancy.owner.manage",
        );
        const body = await readJsonObject(request);
        const source = typeof body.source === "string" ? body.source : "";
        const supportedSources = new Set([
          "lmp",
          "clinician_ultrasound",
          "manual_correction",
          "imported",
          "system_reconciliation",
        ]);
        if (!supportedSources.has(source)) {
          throw new ApiError(
            400,
            "pregnancy_dating_source_invalid",
            "Dating source is invalid.",
          );
        }
        const episode = await store.reviseDating({
          motherPersonId: personId,
          episodeId,
          expectedVersion: requiredInteger(
            body.expectedVersion,
            "pregnancy_version_invalid",
          ),
          dating: {
            method: requireDatingMethod(body.method),
            lmpDate: optionalIsoDate(body.lmpDate, "pregnancy_lmp_invalid"),
            estimatedDueDate: optionalIsoDate(
              body.estimatedDueDate,
              "pregnancy_edd_invalid",
            ),
            referenceDate: optionalIsoDate(
              body.referenceDate,
              "pregnancy_reference_date_invalid",
            ),
            gestationalAgeAtReferenceDays: normalizeReferenceDays(
              body.gestationalAgeAtReferenceDays,
            ),
          },
          source: source as
            | "lmp"
            | "clinician_ultrasound"
            | "manual_correction"
            | "imported"
            | "system_reconciliation",
          reasonCode: typeof body.reasonCode === "string"
            ? body.reasonCode.trim().slice(0, 64)
            : null,
          idempotencyKey: requireMutationIdempotencyKey(request),
          actorAccountId: appUserId,
        });
        return json({
          contractVersion: 1,
          episode: pregnancyEpisodeReadModel(episode, null),
        });
      }

      const endMatch = path.match(
        /^\/api\/v1\/cocoon\/pregnancy\/episodes\/([0-9a-f-]{36})\/end$/i,
      );
      if (request.method === "POST" && endMatch) {
        const episodeId = requiredUuid(
          endMatch[1],
          "pregnancy_episode_id_invalid",
        );
        await requireAccess(
          appUserId,
          personId,
          episodeId,
          "pregnancy.owner.manage",
        );
        const body = await readJsonObject(request);
        const episode = await store.endEpisode({
          motherPersonId: personId,
          episodeId,
          expectedVersion: requiredInteger(
            body.expectedVersion,
            "pregnancy_version_invalid",
          ),
          outcome: requireOutcome(body.outcome),
          idempotencyKey: requireMutationIdempotencyKey(request),
          actorAccountId: appUserId,
        });
        return json({
          contractVersion: 1,
          episode: pregnancyEpisodeReadModel(episode, null),
        });
      }

      return null;
    } catch (error) {
      if (
        error instanceof PregnancyStoreError ||
        error instanceof PregnancyDatingError
      ) {
        mapPregnancyStoreError(error);
      }
      throw error;
    }
  };
}

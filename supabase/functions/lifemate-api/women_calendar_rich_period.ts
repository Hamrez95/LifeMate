import { getLifeMateSql } from "./database_client.ts";
import { createWomenCalendarV3Store } from "./women_calendar_v3.ts";
import { createWomenCircleStore } from "./women_circle_store.ts";
import { ApiError } from "./validation.ts";
import {
  canonicalizeLegacySymptoms,
  mergeLegacySymptomsIntoObservations,
  projectCanonicalSymptomsToLegacy,
  womenSymptomCatalogVersion,
} from "./women_symptom_catalog.ts";
import {
  mapStoredPeriodObservation,
  normalizePeriodObservation,
  periodObservationSchemaVersion,
} from "./women_period_observation.ts";

type Row = Record<string, any>;

export function createWomenCalendarRichPeriodStore(databaseUrl: string) {
  const sql = getLifeMateSql(databaseUrl);
  const base = createWomenCalendarV3Store(databaseUrl);
  const circles = createWomenCircleStore(databaseUrl);

  async function getOwnerProfile(
    appUserId: string,
  ): Promise<Record<string, unknown>> {
    const profile = await base.getOwnerProfile(appUserId);
    return {
      ...profile,
      circles: await circles.list(appUserId),
      circleInvitations: await circles.listIncomingInvitations(appUserId),
    };
  }

  async function updateOwnerProfile(
    appUserId: string,
    body: Record<string, unknown>,
  ): Promise<Record<string, unknown>> {
    const command = body.circleCommand;
    if (command != null) {
      if (typeof command !== "object" || Array.isArray(command)) {
        throw new ApiError(
          400,
          "invalid_circle_command",
          "circleCommand must be an object.",
        );
      }
      await circles.execute(appUserId, command as Record<string, unknown>);
      return await getOwnerProfile(appUserId);
    }
    const profile = await base.updateOwnerProfile(appUserId, body);
    return {
      ...profile,
      circles: await circles.list(appUserId),
      circleInvitations: await circles.listIncomingInvitations(appUserId),
    };
  }

  async function listOwnerDailyLogs(
    appUserId: string,
    fromValue: unknown,
    toValue: unknown,
  ): Promise<Record<string, unknown>[]> {
    const personId = await selfPersonId(sql, appUserId);
    const fromDate = requiredDate(fromValue, "fromDate");
    const toDate = requiredDate(toValue, "toDate");
    if (
      daysBetween(fromDate, toDate) < 0 || daysBetween(fromDate, toDate) > 90
    ) {
      throw new ApiError(400, "invalid_date_range", "Date range is invalid.");
    }
    const rows = await sql`
      select * from lifemate.women_calendar_daily_logs
      where owner_person_id=${personId}::uuid
        and logged_on between ${fromDate}::date and ${toDate}::date
      order by logged_on desc,id
      limit 180
    `;
    return rows.map(mapRichDailyLog);
  }

  async function upsertOwnerDailyLog(
    appUserId: string,
    body: Record<string, unknown>,
  ): Promise<Record<string, unknown>> {
    const hasRichPeriodPatch = [
      "periodFlow",
      "bloodAppearance",
      "bloodTexture",
      "painLevel",
      "symptoms",
      "privateNotes",
      "delete",
    ].some((key) => Object.hasOwn(body, key));
    if (!hasRichPeriodPatch) {
      return await base.upsertOwnerDailyLog(appUserId, body);
    }

    const loggedOn = requiredDate(body.loggedOn, "loggedOn");
    const expectedVersion = nonNegativeInt(body.version ?? 0, "version");
    const shouldDelete = body.delete === true;
    const observation = normalizePeriodObservation(body);
    const painProvided = Object.hasOwn(body, "painLevel");
    const painLevel = painProvided ? optionalPain(body.painLevel) : null;
    const symptomsProvided = Object.hasOwn(body, "symptoms");
    const canonicalSymptoms = symptomsProvided
      ? canonicalizeLegacySymptoms(body.symptoms)
      : [];
    const legacySymptoms = projectCanonicalSymptomsToLegacy(canonicalSymptoms);
    const symptomObservations = canonicalSymptoms.map((id) => ({
      id,
      severity: null,
    }));
    const privateNotesProvided = Object.hasOwn(body, "privateNotes");
    const privateNotes = privateNotesProvided
      ? optionalNote(body.privateNotes)
      : null;

    return await sql.begin(async (tx: any) => {
      const personId = await selfPersonId(tx, appUserId);
      const existingRows = await tx`
        select * from lifemate.women_calendar_daily_logs
        where owner_person_id=${personId}::uuid
          and logged_on=${loggedOn}::date
        for update
      `;
      const existing = existingRows[0] as Row | undefined;

      if (shouldDelete) {
        if (!existing) {
          return {
            deleted: true,
            loggedOn,
            version: 0,
            idempotentReplay: true,
          };
        }
        if (Number(existing.version) !== expectedVersion) throw staleDailyLog();
        await tx`
          delete from lifemate.women_calendar_daily_logs
          where id=${existing.id}::uuid
            and owner_person_id=${personId}::uuid
        `;
        await audit(
          tx,
          appUserId,
          "women_calendar.daily_log_deleted",
          String(existing.id),
        );
        return {
          deleted: true,
          loggedOn,
          version: Number(existing.version) + 1,
        };
      }

      if (!existing) {
        if (expectedVersion !== 0) throw staleDailyLog();
        const id = crypto.randomUUID();
        const storedPain = painProvided && painLevel != null ? painLevel : 0;
        const rows = await tx`
          insert into lifemate.women_calendar_daily_logs(
            id,owner_user_id,owner_person_id,logged_on,mood,energy_level,pain_level,
            pain_recorded,symptoms,symptom_observations,symptom_schema_version,
            private_notes,share_summary_with_companion,
            period_flow,blood_appearance,blood_texture,
            period_observation_schema_version,version,created_at_utc,updated_at_utc
          ) values (
            ${id}::uuid,${appUserId}::uuid,${personId}::uuid,${loggedOn}::date,
            'Neutral',3,${storedPain},${painProvided && painLevel != null},
            ${legacySymptoms}::varchar[],${tx.json(symptomObservations)}::jsonb,
            ${womenSymptomCatalogVersion},${privateNotes},false,
            ${observation.periodFlow},${observation.bloodAppearance},${observation.bloodTexture},
            ${periodObservationSchemaVersion},1,now(),now()
          ) returning *
        `;
        await audit(tx, appUserId, "women_calendar.daily_log_created", id);
        return mapRichDailyLog(rows[0]);
      }

      if (Number(existing.version) !== expectedVersion) throw staleDailyLog();
      const rows = await tx`
        update lifemate.women_calendar_daily_logs
        set period_flow=case when ${
        Object.hasOwn(body, "periodFlow")
      } then ${observation.periodFlow} else period_flow end,
            blood_appearance=case when ${
        Object.hasOwn(body, "bloodAppearance")
      } then ${observation.bloodAppearance} else blood_appearance end,
            blood_texture=case when ${
        Object.hasOwn(body, "bloodTexture")
      } then ${observation.bloodTexture} else blood_texture end,
            period_observation_schema_version=${periodObservationSchemaVersion},
            pain_level=case when ${painProvided && painLevel != null} then ${
        painLevel ?? 0
      } else pain_level end,
            pain_recorded=case when ${painProvided} then ${
        painLevel != null
      } else pain_recorded end,
            symptoms=case when ${symptomsProvided} then ${legacySymptoms}::varchar[] else symptoms end,
            symptom_observations=case when ${symptomsProvided} then ${tx.json(symptomObservations)}::jsonb else symptom_observations end,
            symptom_schema_version=case when ${symptomsProvided} then ${womenSymptomCatalogVersion} else symptom_schema_version end,
            private_notes=case when ${privateNotesProvided} then ${privateNotes} else private_notes end,
            version=version+1,
            updated_at_utc=now()
        where id=${existing.id}::uuid
          and owner_person_id=${personId}::uuid
        returning *
      `;
      await audit(
        tx,
        appUserId,
        "women_calendar.daily_log_updated",
        String(existing.id),
      );
      return mapRichDailyLog(rows[0]);
    });
  }

  return {
    ...base,
    getOwnerProfile,
    updateOwnerProfile,
    listOwnerDailyLogs,
    upsertOwnerDailyLog,
  };
}

export function mapRichDailyLog(row: Row): Record<string, unknown> {
  const observation = mapStoredPeriodObservation(row);
  const symptomObservations = mergeLegacySymptomsIntoObservations(
    row.symptoms,
    row.symptom_observations,
  );
  return {
    id: row.id,
    loggedOn: dateString(row.logged_on),
    mood: row.mood == null ? null : String(row.mood).toLowerCase(),
    energyLevel: row.energy_level,
    painLevel: row.pain_recorded === false ? null : row.pain_level,
    symptoms: symptomObservations.map((item) => item.id),
    symptomObservations,
    symptomSchemaVersion: Number(
      row.symptom_schema_version ?? womenSymptomCatalogVersion,
    ),
    privateNotes: row.private_notes,
    shareSummaryWithCompanion: row.share_summary_with_companion === true,
    ...observation,
    version: row.version,
    createdAtUtc: iso(row.created_at_utc),
    updatedAtUtc: iso(row.updated_at_utc),
  };
}

async function selfPersonId(
  connection: any,
  appUserId: string,
): Promise<string> {
  const rows = await connection`
    select core.self_person_id_for_legacy_app_user(${appUserId}::uuid)::text as person_id
  `;
  const personId = rows[0]?.person_id;
  if (typeof personId !== "string" || personId.length === 0) {
    throw new ApiError(
      409,
      "identity_person_mapping_missing",
      "The LifeMate person mapping is unavailable.",
    );
  }
  return personId;
}

async function audit(
  connection: any,
  actorUserId: string,
  action: string,
  resourceId: string,
): Promise<void> {
  await connection`
    insert into lifemate.audit_logs(
      id,actor_user_id,action,resource_type,resource_id,metadata_json,created_at_utc
    ) values (
      ${crypto.randomUUID()}::uuid,${actorUserId}::uuid,${action},
      'women_calendar_daily_log',${resourceId}::uuid,null,now()
    )
  `;
}

function optionalPain(value: unknown): number | null {
  if (value == null || value === "") return null;
  const number = Number(value);
  if (!Number.isInteger(number) || number < 0 || number > 5) {
    throw new ApiError(
      400,
      "invalid_women_calendar_pain",
      "painLevel must be between 0 and 5.",
    );
  }
  return number;
}

function optionalNote(value: unknown): string | null {
  if (value == null) return null;
  const text = String(value).trim();
  if (text.length === 0) return null;
  if (text.length > 500) {
    throw new ApiError(
      400,
      "invalid_women_calendar_private_note",
      "privateNotes must be 500 characters or fewer.",
    );
  }
  return text;
}

function nonNegativeInt(value: unknown, field: string): number {
  const number = Number(value);
  if (!Number.isInteger(number) || number < 0) {
    throw new ApiError(
      400,
      "invalid_integer",
      `${field} must be non-negative.`,
    );
  }
  return number;
}

function requiredDate(value: unknown, field: string): string {
  const text = String(value ?? "").trim();
  if (!/^\d{4}-\d{2}-\d{2}$/.test(text)) {
    throw new ApiError(400, "invalid_date", `${field} must be YYYY-MM-DD.`);
  }
  const date = new Date(`${text}T00:00:00.000Z`);
  if (
    !Number.isFinite(date.getTime()) || date.toISOString().slice(0, 10) !== text
  ) {
    throw new ApiError(400, "invalid_date", `${field} is invalid.`);
  }
  return text;
}

function daysBetween(left: string, right: string): number {
  return Math.round(
    (new Date(`${right}T00:00:00Z`).getTime() -
      new Date(`${left}T00:00:00Z`).getTime()) / 86_400_000,
  );
}

function staleDailyLog(): ApiError {
  return new ApiError(
    409,
    "stale_women_calendar_daily_log",
    "Daily log changed. Refresh and try again.",
  );
}

function dateString(value: unknown): string {
  if (value instanceof Date) return value.toISOString().slice(0, 10);
  return String(value).slice(0, 10);
}

function iso(value: unknown): string | null {
  if (value == null) return null;
  const date = value instanceof Date ? value : new Date(String(value));
  return Number.isFinite(date.getTime()) ? date.toISOString() : null;
}

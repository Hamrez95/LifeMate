import { getLifeMateSql } from "./database_client.ts";
import type { PregnancyDatingMethod } from "./pregnancy_dating.ts";

export type PregnancyEpisodeStatus = "draft" | "active" | "ended";
export type PregnancyOutcome =
  | "delivered"
  | "pregnancy_loss"
  | "other"
  | "unknown";

export type PregnancyEpisode = {
  id: string;
  motherPersonId: string;
  status: PregnancyEpisodeStatus;
  datingMethod: PregnancyDatingMethod | null;
  lmpDate: string | null;
  estimatedDueDate: string | null;
  datingReferenceDate: string | null;
  gestationalAgeAtReferenceDays: number | null;
  outcome: PregnancyOutcome | null;
  activatedAtUtc: string | null;
  endedAtUtc: string | null;
  version: number;
  createdAtUtc: string;
  updatedAtUtc: string;
};

export type PregnancyDatingPatch = {
  method: PregnancyDatingMethod;
  lmpDate: string | null;
  estimatedDueDate: string | null;
  referenceDate: string | null;
  gestationalAgeAtReferenceDays: number | null;
};

export type CreatePregnancyEpisodeInput = {
  motherPersonId: string;
  status: "draft" | "active";
  method: PregnancyDatingMethod | null;
  lmpDate: string | null;
  estimatedDueDate: string | null;
  referenceDate: string | null;
  gestationalAgeAtReferenceDays: number | null;
  idempotencyKey: string;
  actorAccountId?: string | null;
};

export class PregnancyStoreError extends Error {
  constructor(public readonly code: string) {
    super(code);
    this.name = "PregnancyStoreError";
  }
}

type Row = Record<string, any>;

function episodeFromRow(row: Row): PregnancyEpisode {
  return {
    id: String(row.id),
    motherPersonId: String(row.mother_person_id),
    status: row.status as PregnancyEpisodeStatus,
    datingMethod: row.dating_method as PregnancyDatingMethod | null,
    lmpDate: row.lmp_date == null ? null : String(row.lmp_date),
    estimatedDueDate: row.estimated_due_date == null
      ? null
      : String(row.estimated_due_date),
    datingReferenceDate: row.dating_reference_date == null
      ? null
      : String(row.dating_reference_date),
    gestationalAgeAtReferenceDays: row.gestational_age_at_reference_days == null
      ? null
      : Number(row.gestational_age_at_reference_days),
    outcome: row.outcome as PregnancyOutcome | null,
    activatedAtUtc: row.activated_at_utc == null
      ? null
      : new Date(row.activated_at_utc).toISOString(),
    endedAtUtc: row.ended_at_utc == null
      ? null
      : new Date(row.ended_at_utc).toISOString(),
    version: Number(row.version),
    createdAtUtc: new Date(row.created_at_utc).toISOString(),
    updatedAtUtc: new Date(row.updated_at_utc).toISOString(),
  };
}

function requireIdempotencyKey(value: string): string {
  const normalized = value.trim();
  if (normalized.length < 8 || normalized.length > 128) {
    throw new PregnancyStoreError("idempotency_key_invalid");
  }
  return normalized;
}

async function sha256Hex(value: string): Promise<string> {
  const bytes = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

async function lockMother(tx: any, motherPersonId: string): Promise<void> {
  // Serializes create/activate decisions per Person so two concurrent requests
  // cannot race the partial one-active-episode unique index. The lock key is
  // derived from the opaque UUID only and is transaction-scoped.
  await tx`
    select pg_advisory_xact_lock(
      hashtextextended(${motherPersonId}::text, 0)
    )
  `;
}

async function selectEpisodeById(
  sql: any,
  episodeId: string,
  motherPersonId: string,
): Promise<PregnancyEpisode | null> {
  const rows = await sql`
    select *
    from pregnancy.episodes
    where id=${episodeId}::uuid
      and mother_person_id=${motherPersonId}::uuid
    limit 1
  `;
  return rows[0] ? episodeFromRow(rows[0]) : null;
}

export function createPregnancyStore(databaseUrl: string) {
  const sql = getLifeMateSql(databaseUrl);

  async function getCurrentEpisode(
    motherPersonId: string,
  ): Promise<PregnancyEpisode | null> {
    const rows = await sql`
      select *
      from pregnancy.episodes
      where mother_person_id=${motherPersonId}::uuid
        and status='active'
      order by activated_at_utc desc,id
      limit 1
    `;
    return rows[0] ? episodeFromRow(rows[0]) : null;
  }

  async function listHistory(
    motherPersonId: string,
  ): Promise<PregnancyEpisode[]> {
    const rows = await sql`
      select *
      from pregnancy.episodes
      where mother_person_id=${motherPersonId}::uuid
      order by created_at_utc desc,id desc
    `;
    return rows.map(episodeFromRow);
  }

  async function createEpisode(
    input: CreatePregnancyEpisodeInput,
  ): Promise<PregnancyEpisode> {
    const idempotencyHash = await sha256Hex(
      requireIdempotencyKey(input.idempotencyKey),
    );

    return await sql.begin(async (tx: any) => {
      await lockMother(tx, input.motherPersonId);

      const existing = await tx`
        select *
        from pregnancy.episodes
        where mother_person_id=${input.motherPersonId}::uuid
          and creation_idempotency_key_hash=${idempotencyHash}
        limit 1
      `;
      if (existing[0]) return episodeFromRow(existing[0]);

      if (input.status === "active") {
        const active = await tx`
          select id
          from pregnancy.episodes
          where mother_person_id=${input.motherPersonId}::uuid
            and status='active'
          limit 1
        `;
        if (active[0]) {
          throw new PregnancyStoreError("active_pregnancy_exists");
        }
      }

      const rows = await tx`
        insert into pregnancy.episodes(
          mother_person_id,status,dating_method,lmp_date,
          estimated_due_date,dating_reference_date,
          gestational_age_at_reference_days,activated_at_utc,
          creation_idempotency_key_hash
        ) values (
          ${input.motherPersonId}::uuid,
          ${input.status},
          ${input.method},
          ${input.lmpDate}::date,
          ${input.estimatedDueDate}::date,
          ${input.referenceDate}::date,
          ${input.gestationalAgeAtReferenceDays},
          ${input.status === "active" ? new Date() : null},
          ${idempotencyHash}
        )
        returning *
      `;
      const created = rows[0];

      await tx`
        insert into pregnancy.episode_events(
          episode_id,event_type,from_status,to_status,actor_account_id,
          idempotency_key_hash
        ) values (
          ${created.id}::uuid,'created',null,${created.status},
          ${input.actorAccountId ?? null}::uuid,${idempotencyHash}
        )
      `;
      return episodeFromRow(created);
    });
  }

  async function activateEpisode(args: {
    motherPersonId: string;
    episodeId: string;
    expectedVersion: number;
    idempotencyKey: string;
    actorAccountId?: string | null;
  }): Promise<PregnancyEpisode> {
    const hash = await sha256Hex(requireIdempotencyKey(args.idempotencyKey));
    return await sql.begin(async (tx: any) => {
      await lockMother(tx, args.motherPersonId);

      const priorEvent = await tx`
        select 1
        from pregnancy.episode_events
        where episode_id=${args.episodeId}::uuid
          and idempotency_key_hash=${hash}
        limit 1
      `;
      if (priorEvent[0]) {
        const current = await selectEpisodeById(
          tx,
          args.episodeId,
          args.motherPersonId,
        );
        if (!current) throw new PregnancyStoreError("pregnancy_not_found");
        return current;
      }

      const rows = await tx`
        select * from pregnancy.episodes
        where id=${args.episodeId}::uuid
          and mother_person_id=${args.motherPersonId}::uuid
        for update
      `;
      const current = rows[0];
      if (!current) throw new PregnancyStoreError("pregnancy_not_found");
      if (Number(current.version) !== args.expectedVersion) {
        throw new PregnancyStoreError("pregnancy_version_conflict");
      }
      if (current.status !== "draft") {
        throw new PregnancyStoreError("pregnancy_not_draft");
      }

      const anotherActive = await tx`
        select id
        from pregnancy.episodes
        where mother_person_id=${args.motherPersonId}::uuid
          and status='active'
          and id<>${args.episodeId}::uuid
        limit 1
      `;
      if (anotherActive[0]) {
        throw new PregnancyStoreError("active_pregnancy_exists");
      }

      const updated = await tx`
        update pregnancy.episodes
        set status='active',activated_at_utc=now()
        where id=${args.episodeId}::uuid
        returning *
      `;
      await tx`
        insert into pregnancy.episode_events(
          episode_id,event_type,from_status,to_status,actor_account_id,
          idempotency_key_hash
        ) values (
          ${args.episodeId}::uuid,'activated','draft','active',
          ${args.actorAccountId ?? null}::uuid,${hash}
        )
      `;
      return episodeFromRow(updated[0]);
    });
  }

  async function reviseDating(args: {
    motherPersonId: string;
    episodeId: string;
    expectedVersion: number;
    dating: PregnancyDatingPatch;
    source:
      | "lmp"
      | "clinician_ultrasound"
      | "manual_correction"
      | "imported"
      | "system_reconciliation";
    reasonCode?: string | null;
    idempotencyKey: string;
    actorAccountId?: string | null;
  }): Promise<PregnancyEpisode> {
    const hash = await sha256Hex(requireIdempotencyKey(args.idempotencyKey));
    return await sql.begin(async (tx: any) => {
      const prior = await tx`
        select 1 from pregnancy.dating_revisions
        where episode_id=${args.episodeId}::uuid
          and idempotency_key_hash=${hash}
        limit 1
      `;
      if (prior[0]) {
        const current = await selectEpisodeById(
          tx,
          args.episodeId,
          args.motherPersonId,
        );
        if (!current) throw new PregnancyStoreError("pregnancy_not_found");
        return current;
      }

      const currentRows = await tx`
        select * from pregnancy.episodes
        where id=${args.episodeId}::uuid
          and mother_person_id=${args.motherPersonId}::uuid
        for update
      `;
      const current = currentRows[0];
      if (!current) throw new PregnancyStoreError("pregnancy_not_found");
      if (Number(current.version) !== args.expectedVersion) {
        throw new PregnancyStoreError("pregnancy_version_conflict");
      }
      if (current.status === "ended") {
        throw new PregnancyStoreError("pregnancy_ended");
      }

      const sequenceRows = await tx`
        select coalesce(max(revision_number),0)+1 as next_revision
        from pregnancy.dating_revisions
        where episode_id=${args.episodeId}::uuid
      `;
      const revisionNumber = Number(sequenceRows[0].next_revision);

      await tx`
        insert into pregnancy.dating_revisions(
          episode_id,revision_number,
          previous_dating_method,new_dating_method,
          previous_lmp_date,new_lmp_date,
          previous_estimated_due_date,new_estimated_due_date,
          previous_reference_date,new_reference_date,
          previous_gestational_age_at_reference_days,
          new_gestational_age_at_reference_days,
          source,actor_account_id,reason_code,idempotency_key_hash
        ) values (
          ${args.episodeId}::uuid,${revisionNumber},
          ${current.dating_method},${args.dating.method},
          ${current.lmp_date}::date,${args.dating.lmpDate}::date,
          ${current.estimated_due_date}::date,
          ${args.dating.estimatedDueDate}::date,
          ${current.dating_reference_date}::date,
          ${args.dating.referenceDate}::date,
          ${current.gestational_age_at_reference_days},
          ${args.dating.gestationalAgeAtReferenceDays},
          ${args.source},${args.actorAccountId ?? null}::uuid,
          ${args.reasonCode ?? null},${hash}
        )
      `;

      const updated = await tx`
        update pregnancy.episodes
        set dating_method=${args.dating.method},
            lmp_date=${args.dating.lmpDate}::date,
            estimated_due_date=${args.dating.estimatedDueDate}::date,
            dating_reference_date=${args.dating.referenceDate}::date,
            gestational_age_at_reference_days=
              ${args.dating.gestationalAgeAtReferenceDays}
        where id=${args.episodeId}::uuid
        returning *
      `;
      await tx`
        insert into pregnancy.episode_events(
          episode_id,event_type,from_status,to_status,actor_account_id,
          idempotency_key_hash
        ) values (
          ${args.episodeId}::uuid,'dating_revised',${current.status},
          ${current.status},${args.actorAccountId ?? null}::uuid,${hash}
        )
      `;
      return episodeFromRow(updated[0]);
    });
  }

  async function endEpisode(args: {
    motherPersonId: string;
    episodeId: string;
    expectedVersion: number;
    outcome: PregnancyOutcome;
    idempotencyKey: string;
    actorAccountId?: string | null;
  }): Promise<PregnancyEpisode> {
    const hash = await sha256Hex(requireIdempotencyKey(args.idempotencyKey));
    return await sql.begin(async (tx: any) => {
      const prior = await tx`
        select 1 from pregnancy.episode_events
        where episode_id=${args.episodeId}::uuid
          and idempotency_key_hash=${hash}
        limit 1
      `;
      if (prior[0]) {
        const current = await selectEpisodeById(
          tx,
          args.episodeId,
          args.motherPersonId,
        );
        if (!current) throw new PregnancyStoreError("pregnancy_not_found");
        return current;
      }

      const currentRows = await tx`
        select * from pregnancy.episodes
        where id=${args.episodeId}::uuid
          and mother_person_id=${args.motherPersonId}::uuid
        for update
      `;
      const current = currentRows[0];
      if (!current) throw new PregnancyStoreError("pregnancy_not_found");
      if (Number(current.version) !== args.expectedVersion) {
        throw new PregnancyStoreError("pregnancy_version_conflict");
      }
      if (current.status === "ended") {
        throw new PregnancyStoreError("pregnancy_already_ended");
      }

      const updated = await tx`
        update pregnancy.episodes
        set status='ended',outcome=${args.outcome},ended_at_utc=now()
        where id=${args.episodeId}::uuid
        returning *
      `;
      await tx`
        insert into pregnancy.episode_events(
          episode_id,event_type,from_status,to_status,outcome,
          actor_account_id,idempotency_key_hash
        ) values (
          ${args.episodeId}::uuid,'ended',${current.status},'ended',
          ${args.outcome},${args.actorAccountId ?? null}::uuid,${hash}
        )
      `;
      return episodeFromRow(updated[0]);
    });
  }

  return {
    getCurrentEpisode,
    listHistory,
    createEpisode,
    activateEpisode,
    reviseDating,
    endEpisode,
  };
}

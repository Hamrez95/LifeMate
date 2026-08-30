import { type AdminSql, getAdminSql } from "./database_client.ts";
import {
  evaluateSegmentRuleSet,
  type SegmentAttribute,
  type SegmentRuleSet,
  type SegmentSubject,
} from "./audience_segments.ts";
import { ApiError } from "./validation.ts";

const MIN_PREVIEW_COHORT = 10;
const MAX_EVALUATION_SUBJECTS = 50_000;
const SUPPORTED_SOURCE_ATTRIBUTES = new Set<SegmentAttribute>([
  "demographic.age_years",
  "demographic.age_bucket",
  "demographic.birthday_month",
  "demographic.birthday_day",
  "demographic.birthday_upcoming_days",
  "demographic.gender_identity",
  "demographic.locale",
  "product.code",
  "product.enrolled",
  "subscription.status",
  "entitlement.code",
  "engagement.lifecycle",
  "engagement.last_active_days",
]);

type SegmentRecord = {
  id: string;
  key: string;
  name: string;
  description: string | null;
  ruleSet: SegmentRuleSet;
  ruleHash: string;
  status: string;
  version: number;
  createdAtUtc: string;
  updatedAtUtc: string;
};

type SubjectRow = {
  account_id: unknown;
  person_id: unknown;
  locale: unknown;
  time_zone: unknown;
  birth_date: unknown;
  gender_identity: unknown;
  application_codes: unknown;
  last_active_at_utc: unknown;
  product_codes: unknown;
  subscription_statuses: unknown;
  entitlement_codes: unknown;
};

function iso(value: unknown): string {
  return new Date(String(value)).toISOString();
}

function stringArray(value: unknown): string[] {
  return Array.isArray(value)
    ? value.filter((item): item is string => typeof item === "string")
    : [];
}

function normalizedArray(value: unknown): string[] {
  return stringArray(value)
    .map((item) => item.trim().toLowerCase())
    .filter(Boolean);
}

function mapSegment(row: Record<string, unknown>): SegmentRecord {
  return {
    id: String(row.id),
    key: String(row.segment_key),
    name: String(row.name),
    description: row.description == null ? null : String(row.description),
    ruleSet: row.rule_json as SegmentRuleSet,
    ruleHash: String(row.rule_hash),
    status: String(row.status),
    version: Number(row.version),
    createdAtUtc: iso(row.created_at_utc),
    updatedAtUtc: iso(row.updated_at_utc),
  };
}

function lifecycle(lastActiveAtUtc: unknown): { days: number | null; label: string } {
  if (lastActiveAtUtc == null) return { days: null, label: "never_active" };
  const timestamp = new Date(String(lastActiveAtUtc)).getTime();
  if (!Number.isFinite(timestamp)) return { days: null, label: "never_active" };
  const millis = Date.now() - timestamp;
  const days = Math.max(0, Math.floor(millis / 86_400_000));
  if (days <= 7) return { days, label: "active_7d" };
  if (days <= 30) return { days, label: "active_30d" };
  if (days <= 90) return { days, label: "dormant_31_90d" };
  return { days, label: "inactive_90d_plus" };
}

type DateOnly = { year: number; month: number; day: number };

function parseDateOnly(value: unknown): DateOnly | null {
  if (value == null) return null;
  const match = /^(\d{4})-(\d{2})-(\d{2})/.exec(String(value));
  if (!match) return null;
  const result = { year: Number(match[1]), month: Number(match[2]), day: Number(match[3]) };
  if (
    !Number.isInteger(result.year) || result.year < 1800 || result.year > 2200 ||
    result.month < 1 || result.month > 12 || result.day < 1 || result.day > 31
  ) return null;
  return result;
}

function localDate(now: Date, timeZoneValue: unknown): DateOnly {
  const timeZone = typeof timeZoneValue === "string" && timeZoneValue.trim()
    ? timeZoneValue.trim()
    : "UTC";
  try {
    const parts = new Intl.DateTimeFormat("en-CA", {
      timeZone,
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
    }).formatToParts(now);
    const values = Object.fromEntries(parts.map((part) => [part.type, part.value]));
    return { year: Number(values.year), month: Number(values.month), day: Number(values.day) };
  } catch {
    return { year: now.getUTCFullYear(), month: now.getUTCMonth() + 1, day: now.getUTCDate() };
  }
}

function ageYears(birth: DateOnly, today: DateOnly): number | null {
  if (birth.year > today.year) return null;
  let age = today.year - birth.year;
  if (today.month < birth.month || (today.month === birth.month && today.day < birth.day)) age -= 1;
  return age >= 0 && age <= 130 ? age : null;
}

function ageBucket(age: number): string {
  if (age < 18) return "under_18";
  if (age <= 24) return "18_24";
  if (age <= 34) return "25_34";
  if (age <= 44) return "35_44";
  if (age <= 54) return "45_54";
  if (age <= 64) return "55_64";
  return "65_plus";
}

function daysInMonth(year: number, month: number): number {
  return new Date(Date.UTC(year, month, 0)).getUTCDate();
}

function dateOrdinal(value: DateOnly): number {
  return Math.floor(Date.UTC(value.year, value.month - 1, value.day) / 86_400_000);
}

export function birthdayDaysUntil(birth: DateOnly, today: DateOnly): number {
  const birthdayIn = (year: number): DateOnly => ({
    year,
    month: birth.month,
    // Canonical leap-day policy: celebrate Feb 29 on Feb 28 in non-leap years.
    day: Math.min(birth.day, daysInMonth(year, birth.month)),
  });
  let next = birthdayIn(today.year);
  if (dateOrdinal(next) < dateOrdinal(today)) next = birthdayIn(today.year + 1);
  return Math.max(0, dateOrdinal(next) - dateOrdinal(today));
}

function normalizedGender(value: unknown): string | null {
  const map: Record<string, string> = {
    Woman: "woman",
    Man: "man",
    NonBinary: "non_binary",
    SelfDescribe: "self_describe",
    PreferNotToSay: "prefer_not_to_say",
  };
  return typeof value === "string" ? map[value] ?? null : null;
}

export function projectDemographicSubject(
  row: Pick<SubjectRow, "locale" | "time_zone" | "birth_date" | "gender_identity">,
  now = new Date(),
): SegmentSubject {
  const subject: SegmentSubject = {};
  const locale = typeof row.locale === "string" ? row.locale.trim() : "";
  if (locale) subject["demographic.locale"] = locale;

  const gender = normalizedGender(row.gender_identity);
  if (gender) subject["demographic.gender_identity"] = gender;

  const birth = parseDateOnly(row.birth_date);
  if (birth) {
    const today = localDate(now, row.time_zone);
    const age = ageYears(birth, today);
    if (age !== null) {
      subject["demographic.age_years"] = age;
      subject["demographic.age_bucket"] = ageBucket(age);
    }
    subject["demographic.birthday_month"] = birth.month;
    subject["demographic.birthday_day"] = birth.day;
    subject["demographic.birthday_upcoming_days"] = birthdayDaysUntil(birth, today);
  }
  return subject;
}

function toSubject(row: SubjectRow): SegmentSubject {
  const products = Array.from(new Set([
    ...normalizedArray(row.application_codes),
    ...normalizedArray(row.product_codes),
  ]));
  const activity = lifecycle(row.last_active_at_utc);
  const subject: SegmentSubject = {
    ...projectDemographicSubject(row),
    "product.code": products,
    "product.enrolled": products.length > 0,
    "subscription.status": normalizedArray(row.subscription_statuses),
    "entitlement.code": normalizedArray(row.entitlement_codes),
    "engagement.lifecycle": activity.label,
  };
  if (activity.days !== null) subject["engagement.last_active_days"] = activity.days;
  return subject;
}

function unsupportedAttributes(ruleSet: SegmentRuleSet): SegmentAttribute[] {
  return Array.from(new Set(
    ruleSet.rules
      .map((rule) => rule.attribute)
      .filter((attribute) => !SUPPORTED_SOURCE_ATTRIBUTES.has(attribute)),
  ));
}

async function loadSubjects(sql: AdminSql): Promise<SubjectRow[]> {
  const rows = await sql<SubjectRow[]>`
    select
      d.account_id,
      d.person_id,
      pp.locale,
      pp.time_zone,
      person.birth_date,
      pp.gender_identity,
      d.application_codes,
      d.last_active_at_utc,
      coalesce((
        select array_agg(distinct lower(p.code) order by lower(p.code))
        from commerce.subscriptions s
        join commerce.products p on p.id=s.product_id
        where (s.owner_account_id=d.account_id or s.beneficiary_person_id=d.person_id)
      ),array[]::varchar[]) as product_codes,
      coalesce((
        select array_agg(distinct lower(s.status) order by lower(s.status))
        from commerce.subscriptions s
        where (s.owner_account_id=d.account_id or s.beneficiary_person_id=d.person_id)
      ),array[]::varchar[]) as subscription_statuses,
      coalesce((
        select array_agg(distinct lower(f.code) order by lower(f.code))
        from commerce.entitlements e
        join commerce.features f on f.id=e.feature_id
        where (e.grantee_account_id=d.account_id or e.beneficiary_person_id=d.person_id)
          and e.status='Active'
          and e.starts_at_utc <= now()
          and (e.expires_at_utc is null or e.expires_at_utc > now())
      ),array[]::varchar[]) as entitlement_codes
    from admin.user_directory_v2 d
    left join core.person_profiles pp on pp.person_id=d.person_id
    left join core.persons person on person.id=d.person_id
    order by d.account_id
    limit ${MAX_EVALUATION_SUBJECTS + 1}
  `;
  if (rows.length > MAX_EVALUATION_SUBJECTS) {
    throw new ApiError(
      503,
      "segment_evaluation_capacity_exceeded",
      "Audience evaluation exceeded the current bounded subject capacity.",
    );
  }
  return rows;
}

async function consumeIdempotency<T>(input: {
  sql: AdminSql;
  actorAccountId: string;
  operation: string;
  idempotencyKey: string;
  requestHash: string;
  work: (tx: AdminSql) => Promise<T>;
}): Promise<T> {
  return await input.sql.begin(async (tx) => {
    const inserted = await tx`
      insert into admin.idempotency_keys(
        actor_account_id,operation,idempotency_key,request_hash,status,expires_at_utc
      ) values (
        ${input.actorAccountId}::uuid,${input.operation},${input.idempotencyKey},${input.requestHash},'Processing',now()+interval '24 hours'
      )
      on conflict (actor_account_id,operation,idempotency_key) do nothing
      returning idempotency_key
    `;
    if (inserted.length === 0) {
      const existing = await tx`
        select request_hash,status,response_json
        from admin.idempotency_keys
        where actor_account_id=${input.actorAccountId}::uuid
          and operation=${input.operation}
          and idempotency_key=${input.idempotencyKey}
        for update
      `;
      if (existing.length === 0) {
        throw new ApiError(409,"idempotency_conflict","Idempotency state changed; retry safely.");
      }
      if (String(existing[0].request_hash) !== input.requestHash) {
        throw new ApiError(409,"idempotency_key_reused","Idempotency key was already used with a different request.");
      }
      if (String(existing[0].status) === "Completed") {
        return existing[0].response_json as T;
      }
      throw new ApiError(409,"request_in_progress","An equivalent segment operation is already in progress.");
    }

    const response = await input.work(tx as AdminSql);
    await tx`
      update admin.idempotency_keys
      set status='Completed',response_status=200,response_json=${tx.json(response as object)},updated_at_utc=now()
      where actor_account_id=${input.actorAccountId}::uuid
        and operation=${input.operation}
        and idempotency_key=${input.idempotencyKey}
    `;
    return response;
  }) as T;
}

export function createAudienceSegmentStore(databaseUrl: string) {
  const sql = getAdminSql(databaseUrl);

  async function requireSegment(
    id: string,
    executor: AdminSql = sql,
    lockForSnapshot = false,
  ): Promise<SegmentRecord> {
    const rows = lockForSnapshot
      ? await executor`
          select id,segment_key,name,description,rule_json,rule_hash,status,version,created_at_utc,updated_at_utc
          from audience.segments where id=${id}::uuid limit 1 for share
        `
      : await executor`
          select id,segment_key,name,description,rule_json,rule_hash,status,version,created_at_utc,updated_at_utc
          from audience.segments where id=${id}::uuid limit 1
        `;
    if (rows.length === 0) {
      throw new ApiError(404,"segment_not_found","Audience segment was not found.");
    }
    return mapSegment(rows[0]);
  }

  async function matchingMembers(
    ruleSet: SegmentRuleSet,
    executor: AdminSql = sql,
  ) {
    const unsupported = unsupportedAttributes(ruleSet);
    if (unsupported.length > 0) {
      throw new ApiError(
        409,
        "segment_source_unavailable",
        `Canonical source is not available for: ${unsupported.join(", ")}.`,
      );
    }
    const rows = await loadSubjects(executor);
    return rows.filter((row) => evaluateSegmentRuleSet(ruleSet,toSubject(row)));
  }

  return {
    async list() {
      const rows = await sql`
        select id,segment_key,name,description,rule_json,rule_hash,status,version,created_at_utc,updated_at_utc
        from audience.segments order by segment_key
      `;
      return rows.map(mapSegment);
    },

    get: (id: string) => requireSegment(id),

    async create(input: {
      actorAccountId: string;
      key: string;
      name: string;
      description: string | null;
      ruleSet: SegmentRuleSet;
      ruleHash: string;
      idempotencyKey: string;
      requestHash: string;
      correlationId: string;
    }) {
      return await consumeIdempotency({
        sql,
        actorAccountId: input.actorAccountId,
        operation: "audience.segment.create",
        idempotencyKey: input.idempotencyKey,
        requestHash: input.requestHash,
        work: async (tx) => {
          const rows = await tx`
            insert into audience.segments(
              segment_key,name,description,rule_json,rule_hash,created_by_account_id,updated_by_account_id
            ) values (
              ${input.key},${input.name},${input.description},${tx.json(input.ruleSet)},${input.ruleHash},
              ${input.actorAccountId}::uuid,${input.actorAccountId}::uuid
            )
            on conflict (segment_key) do nothing
            returning id,segment_key,name,description,rule_json,rule_hash,status,version,created_at_utc,updated_at_utc
          `;
          if (rows.length === 0) {
            throw new ApiError(409,"segment_key_conflict","Audience segment key already exists.");
          }
          const segment = mapSegment(rows[0]);
          await tx`
            insert into admin.audit_events(
              actor_account_id,action,resource_type,resource_id,result,reason,correlation_id,request_id,elevated_access,metadata_json
            ) values (
              ${input.actorAccountId}::uuid,'audience.segment.create','audience_segment',${segment.id},'Succeeded',
              'Create reusable audience segment',${input.correlationId}::uuid,${input.idempotencyKey},false,
              ${tx.json({segmentKey:segment.key,ruleHash:segment.ruleHash,version:segment.version})}
            )
          `;
          return segment;
        },
      });
    },

    async update(input: {
      actorAccountId: string;
      id: string;
      expectedVersion: number;
      name: string;
      description: string | null;
      ruleSet: SegmentRuleSet;
      ruleHash: string;
      status: "Active" | "Archived";
      idempotencyKey: string;
      requestHash: string;
      correlationId: string;
    }) {
      return await consumeIdempotency({
        sql,
        actorAccountId: input.actorAccountId,
        operation: `audience.segment.update:${input.id}`,
        idempotencyKey: input.idempotencyKey,
        requestHash: input.requestHash,
        work: async (tx) => {
          const rows = await tx`
            update audience.segments
            set name=${input.name},description=${input.description},rule_json=${tx.json(input.ruleSet)},
                rule_hash=${input.ruleHash},status=${input.status},version=version+1,
                updated_by_account_id=${input.actorAccountId}::uuid,updated_at_utc=now()
            where id=${input.id}::uuid and version=${input.expectedVersion}
            returning id,segment_key,name,description,rule_json,rule_hash,status,version,created_at_utc,updated_at_utc
          `;
          if (rows.length === 0) {
            const exists = await tx`select version from audience.segments where id=${input.id}::uuid limit 1`;
            if (exists.length === 0) throw new ApiError(404,"segment_not_found","Audience segment was not found.");
            throw new ApiError(409,"segment_version_conflict","Audience segment changed; refresh before updating.");
          }
          const segment = mapSegment(rows[0]);
          await tx`
            insert into admin.audit_events(
              actor_account_id,action,resource_type,resource_id,result,reason,correlation_id,request_id,elevated_access,metadata_json
            ) values (
              ${input.actorAccountId}::uuid,'audience.segment.update','audience_segment',${segment.id},'Succeeded',
              'Update reusable audience segment',${input.correlationId}::uuid,${input.idempotencyKey},false,
              ${tx.json({segmentKey:segment.key,ruleHash:segment.ruleHash,version:segment.version,status:segment.status})}
            )
          `;
          return segment;
        },
      });
    },

    async preview(id: string) {
      const segment = await requireSegment(id);
      const members = await matchingMembers(segment.ruleSet);
      const count = members.length;
      return {
        segmentId: segment.id,
        segmentVersion: segment.version,
        ruleHash: segment.ruleHash,
        count: count > 0 && count < MIN_PREVIEW_COHORT ? null : count,
        suppressed: count > 0 && count < MIN_PREVIEW_COHORT,
        minimumCohortSize: MIN_PREVIEW_COHORT,
        source: "canonical_account_person_demographic_commerce_projection_v2",
        sourceAsOfUtc: new Date().toISOString(),
      };
    },

    async snapshot(input: {
      actorAccountId: string;
      id: string;
      expectedVersion: number;
      idempotencyKey: string;
      requestHash: string;
      correlationId: string;
    }) {
      return await consumeIdempotency({
        sql,
        actorAccountId: input.actorAccountId,
        operation: `audience.segment.snapshot:${input.id}:${input.expectedVersion}`,
        idempotencyKey: input.idempotencyKey,
        requestHash: input.requestHash,
        work: async (tx) => {
          const segment = await requireSegment(input.id, tx, true);
          if (segment.status !== "Active") {
            throw new ApiError(
              409,
              "segment_not_active",
              "Audience segment must be active before creating an execution snapshot.",
            );
          }
          if (segment.version !== input.expectedVersion) {
            throw new ApiError(
              409,
              "segment_version_conflict",
              "Audience segment changed; refresh before creating an execution snapshot.",
            );
          }

          const members = await matchingMembers(segment.ruleSet, tx);
          const sourceAsOfUtc = new Date().toISOString();
          const snapshots = await tx`
            insert into audience.segment_snapshots(
              segment_id,segment_version,rule_hash,source_as_of_utc,member_count,created_by_account_id
            ) values (
              ${segment.id}::uuid,${segment.version},${segment.ruleHash},${sourceAsOfUtc}::timestamptz,${members.length},${input.actorAccountId}::uuid
            ) returning id,created_at_utc
          `;
          const snapshotId = String(snapshots[0].id);
          for (const member of members) {
            await tx`
              insert into audience.segment_snapshot_members(snapshot_id,account_id,person_id)
              values (${snapshotId}::uuid,${String(member.account_id)}::uuid,${member.person_id == null ? null : String(member.person_id)}::uuid)
            `;
          }
          await tx`
            insert into admin.audit_events(
              actor_account_id,action,resource_type,resource_id,result,reason,correlation_id,request_id,elevated_access,metadata_json
            ) values (
              ${input.actorAccountId}::uuid,'audience.segment.snapshot','audience_segment_snapshot',${snapshotId},'Succeeded',
              'Create immutable audience execution snapshot',${input.correlationId}::uuid,${input.idempotencyKey},false,
              ${tx.json({segmentId:segment.id,segmentVersion:segment.version,ruleHash:segment.ruleHash,memberCount:members.length})}
            )
          `;
          return {
            id: snapshotId,
            segmentId: segment.id,
            segmentVersion: segment.version,
            ruleHash: segment.ruleHash,
            memberCount: members.length,
            sourceAsOfUtc,
            createdAtUtc: iso(snapshots[0].created_at_utc),
          };
        },
      });
    },

    sourceCapabilities() {
      return {
        supportedAttributes: [...SUPPORTED_SOURCE_ATTRIBUTES],
        unavailableAttributes: ["campaign.channel", "campaign.last_outcome"],
        minimumPreviewCohort: MIN_PREVIEW_COHORT,
      };
    },
  };
}

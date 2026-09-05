import { getLifeMateSql } from "./database_client.ts";
import { ApiError } from "./validation.ts";
import {
  aggregateCirclePlanningWindow,
  deriveCirclePlanningContribution,
  normalizeCircleSharingPolicy,
} from "./women_circle_planning.ts";
import { calculateWomenCalendarEstimateFromEpisodes } from "./women_calendar_legacy.ts";

type Row = Record<string, any>;

type CircleCommand =
  | { action: "create"; name: string; iconKey?: string | null }
  | { action: "invite"; circleId: string; inviteeAppUserId: string }
  | {
    action: "respond_invite";
    invitationId: string;
    response: "accept" | "decline";
  }
  | {
    action: "set_sharing";
    circleId: string;
    mode: string;
    includePeriodWindow?: boolean;
    includePhaseContext?: boolean;
    includeWellbeingContext?: boolean;
    version?: number;
  }
  | { action: "leave"; circleId: string }
  | { action: "remove_member"; circleId: string; memberPersonId: string }
  | { action: "close"; circleId: string };

export function createWomenCircleStore(databaseUrl: string) {
  const sql = getLifeMateSql(databaseUrl);

  async function list(appUserId: string): Promise<Record<string, unknown>[]> {
    const personId = await selfPersonId(sql, appUserId);
    const circles = await sql`
      select distinct c.*
      from network.circles c
      left join network.circle_members m on m.circle_id=c.id
      where c.circle_kind='women_health_planning'
        and c.status='active'
        and (
          c.owner_person_id=${personId}::uuid
          or (m.person_id=${personId}::uuid and m.membership_status='active')
        )
      order by c.updated_at_utc desc,c.created_at_utc desc
      limit 50
    `;
    const result: Record<string, unknown>[] = [];
    for (const circle of circles) {
      result.push(await mapCircle(sql, circle, personId));
    }
    return result;
  }

  async function listIncomingInvitations(
    appUserId: string,
  ): Promise<Record<string, unknown>[]> {
    const personId = await selfPersonId(sql, appUserId);
    const rows = await sql`
      select i.id,i.circle_id,i.status,i.expires_at_utc,i.created_at_utc,
             c.name,c.icon_key,
             p.display_name as inviter_display_name
      from network.circle_invitations i
      join network.circles c on c.id=i.circle_id and c.status='active'
      left join core.person_profiles p on p.person_id=i.inviter_person_id
      where i.invitee_person_id=${personId}::uuid
        and i.status='pending'
        and i.expires_at_utc>now()
      order by i.created_at_utc desc
      limit 30
    `;
    return rows.map((row: Row) => ({
      id: String(row.id),
      circleId: String(row.circle_id),
      circleName: String(row.name),
      iconKey: text(row.icon_key),
      inviterDisplayName: text(row.inviter_display_name) ?? "LifeMate User",
      expiresAtUtc: iso(row.expires_at_utc),
    }));
  }

  async function execute(
    appUserId: string,
    raw: Record<string, unknown>,
  ): Promise<Record<string, unknown>> {
    const command = normalizeCommand(raw);
    const actorPersonId = await selfPersonId(sql, appUserId);
    if (command.action === "create") {
      return await sql.begin(async (tx: any) => {
        const id = crypto.randomUUID();
        const rows = await tx`
          insert into network.circles(id,owner_person_id,circle_kind,name,icon_key,status,version,created_at_utc,updated_at_utc)
          values(${id}::uuid,${actorPersonId}::uuid,'women_health_planning',${command.name},${
          command.iconKey ?? null
        },'active',1,now(),now())
          returning *
        `;
        await tx`
          insert into network.circle_members(id,circle_id,person_id,membership_role,membership_status,joined_at_utc,created_at_utc,updated_at_utc)
          values(${crypto.randomUUID()}::uuid,${id}::uuid,${actorPersonId}::uuid,'owner','active',now(),now(),now())
          on conflict do nothing
        `;
        await tx`
          insert into network.circle_member_sharing_policies(circle_id,person_id,sharing_mode,include_period_window,include_phase_context,include_wellbeing_context,version,created_at_utc,updated_at_utc)
          values(${id}::uuid,${actorPersonId}::uuid,'none',false,false,false,1,now(),now())
          on conflict(circle_id,person_id) do nothing
        `;
        await audit(tx, id, actorPersonId, "circle.created", actorPersonId);
        return await mapCircle(tx, rows[0], actorPersonId);
      });
    }

    if (command.action === "invite") {
      const inviteePersonId = await selfPersonId(sql, command.inviteeAppUserId);
      if (inviteePersonId === actorPersonId) {
        throw invalid("cannot_invite_self");
      }
      return await sql.begin(async (tx: any) => {
        const circle = await requireOwnerCircle(
          tx,
          command.circleId,
          actorPersonId,
        );
        const existingMember = await tx`
          select 1 from network.circle_members
          where circle_id=${circle.id}::uuid and person_id=${inviteePersonId}::uuid and membership_status='active'
          limit 1
        `;
        if (existingMember[0]) {
          throw new ApiError(
            409,
            "circle_member_exists",
            "Person is already an active Circle member.",
          );
        }
        const existingInvite = await tx`
          select id,expires_at_utc from network.circle_invitations
          where circle_id=${circle.id}::uuid and invitee_person_id=${inviteePersonId}::uuid
            and status='pending' and expires_at_utc>now()
          order by created_at_utc desc limit 1
        `;
        if (existingInvite[0]) {
          return {
            invitationId: String(existingInvite[0].id),
            idempotentReplay: true,
            expiresAtUtc: iso(existingInvite[0].expires_at_utc),
          };
        }
        const invitationId = crypto.randomUUID();
        const rows = await tx`
          insert into network.circle_invitations(id,circle_id,inviter_person_id,invitee_person_id,status,expires_at_utc,created_at_utc,updated_at_utc)
          values(${invitationId}::uuid,${circle.id}::uuid,${actorPersonId}::uuid,${inviteePersonId}::uuid,'pending',now()+interval '7 days',now(),now())
          returning id,expires_at_utc
        `;
        await audit(
          tx,
          String(circle.id),
          actorPersonId,
          "circle.invitation_created",
          inviteePersonId,
        );
        return {
          invitationId: String(rows[0].id),
          expiresAtUtc: iso(rows[0].expires_at_utc),
        };
      });
    }

    if (command.action === "respond_invite") {
      return await sql.begin(async (tx: any) => {
        const invites = await tx`
          select i.*,c.status as circle_status from network.circle_invitations i
          join network.circles c on c.id=i.circle_id
          where i.id=${command.invitationId}::uuid
            and i.invitee_person_id=${actorPersonId}::uuid
          for update
        `;
        const invite = invites[0];
        if (!invite || invite.circle_status !== "active") throw notFound();
        if (invite.status === "accepted" && command.response === "accept") {
          return {
            accepted: true,
            idempotentReplay: true,
            circleId: String(invite.circle_id),
          };
        }
        if (
          invite.status !== "pending" ||
          new Date(invite.expires_at_utc).getTime() <= Date.now()
        ) {
          throw new ApiError(
            409,
            "circle_invitation_not_pending",
            "Circle invitation is no longer pending.",
          );
        }
        if (command.response === "decline") {
          await tx`update network.circle_invitations set status='declined',declined_at_utc=now(),updated_at_utc=now() where id=${invite.id}::uuid`;
          await audit(
            tx,
            String(invite.circle_id),
            actorPersonId,
            "circle.invitation_declined",
            actorPersonId,
          );
          return { accepted: false, circleId: String(invite.circle_id) };
        }
        await tx`update network.circle_invitations set status='accepted',accepted_at_utc=now(),updated_at_utc=now() where id=${invite.id}::uuid`;
        await tx`
          insert into network.circle_members(id,circle_id,person_id,membership_role,membership_status,joined_at_utc,created_at_utc,updated_at_utc)
          values(${crypto.randomUUID()}::uuid,${invite.circle_id}::uuid,${actorPersonId}::uuid,'member','active',now(),now(),now())
          on conflict do nothing
        `;
        await tx`
          insert into network.circle_member_sharing_policies(circle_id,person_id,sharing_mode,include_period_window,include_phase_context,include_wellbeing_context,version,created_at_utc,updated_at_utc)
          values(${invite.circle_id}::uuid,${actorPersonId}::uuid,'none',false,false,false,1,now(),now())
          on conflict(circle_id,person_id) do nothing
        `;
        await audit(
          tx,
          String(invite.circle_id),
          actorPersonId,
          "circle.invitation_accepted",
          actorPersonId,
        );
        return { accepted: true, circleId: String(invite.circle_id) };
      });
    }

    if (command.action === "set_sharing") {
      return await sql.begin(async (tx: any) => {
        await requireActiveMember(tx, command.circleId, actorPersonId);
        const policy = normalizeCircleSharingPolicy({
          mode: command.mode,
          includePeriodWindow: command.includePeriodWindow === true,
          includePhaseContext: command.includePhaseContext === true,
          includeWellbeingContext: command.includeWellbeingContext === true,
        });
        if (command.mode !== "none" && policy.mode === "none") {
          throw invalid("invalid_circle_sharing_mode");
        }
        const existing = await tx`
          select version from network.circle_member_sharing_policies
          where circle_id=${command.circleId}::uuid and person_id=${actorPersonId}::uuid
          for update
        `;
        const version = Number(existing[0]?.version ?? 0);
        if (command.version != null && command.version !== version) {
          throw new ApiError(
            409,
            "stale_circle_sharing_policy",
            "Circle sharing policy changed. Refresh and try again.",
          );
        }
        const rows = await tx`
          insert into network.circle_member_sharing_policies(
            circle_id,person_id,sharing_mode,include_period_window,include_phase_context,include_wellbeing_context,version,created_at_utc,updated_at_utc,revoked_at_utc
          ) values(
            ${command.circleId}::uuid,${actorPersonId}::uuid,${policy.mode},${policy.includePeriodWindow},${policy.includePhaseContext},${policy.includeWellbeingContext},1,now(),now(),${
          policy.mode === "none" ? new Date() : null
        }
          )
          on conflict(circle_id,person_id) do update set
            sharing_mode=excluded.sharing_mode,
            include_period_window=excluded.include_period_window,
            include_phase_context=excluded.include_phase_context,
            include_wellbeing_context=excluded.include_wellbeing_context,
            version=network.circle_member_sharing_policies.version+1,
            updated_at_utc=now(),
            revoked_at_utc=case when excluded.sharing_mode='none' then now() else null end
          returning *
        `;
        await audit(
          tx,
          command.circleId,
          actorPersonId,
          "circle.sharing_updated",
          actorPersonId,
        );
        return mapSharing(rows[0]);
      });
    }

    if (command.action === "leave") {
      return await sql.begin(async (tx: any) => {
        const circle =
          await tx`select * from network.circles where id=${command.circleId}::uuid and status='active' limit 1`;
        if (!circle[0]) throw notFound();
        if (String(circle[0].owner_person_id) === actorPersonId) {
          throw new ApiError(
            409,
            "circle_owner_cannot_leave",
            "Circle owner must close the Circle instead.",
          );
        }
        const rows = await tx`
          update network.circle_members set membership_status='left',left_at_utc=now(),updated_at_utc=now()
          where circle_id=${command.circleId}::uuid and person_id=${actorPersonId}::uuid and membership_status='active'
          returning id
        `;
        if (!rows[0]) throw notFound();
        await tx`update network.circle_member_sharing_policies set sharing_mode='none',include_period_window=false,include_phase_context=false,include_wellbeing_context=false,revoked_at_utc=now(),version=version+1,updated_at_utc=now() where circle_id=${command.circleId}::uuid and person_id=${actorPersonId}::uuid`;
        await audit(
          tx,
          command.circleId,
          actorPersonId,
          "circle.member_left",
          actorPersonId,
        );
        return { left: true };
      });
    }

    if (command.action === "remove_member") {
      return await sql.begin(async (tx: any) => {
        await requireOwnerCircle(tx, command.circleId, actorPersonId);
        if (command.memberPersonId === actorPersonId) {
          throw invalid("cannot_remove_circle_owner");
        }
        const rows = await tx`
          update network.circle_members set membership_status='removed',removed_at_utc=now(),updated_at_utc=now()
          where circle_id=${command.circleId}::uuid and person_id=${command.memberPersonId}::uuid and membership_status='active'
          returning id
        `;
        if (!rows[0]) throw notFound();
        await tx`update network.circle_member_sharing_policies set sharing_mode='none',include_period_window=false,include_phase_context=false,include_wellbeing_context=false,revoked_at_utc=now(),version=version+1,updated_at_utc=now() where circle_id=${command.circleId}::uuid and person_id=${command.memberPersonId}::uuid`;
        await audit(
          tx,
          command.circleId,
          actorPersonId,
          "circle.member_removed",
          command.memberPersonId,
        );
        return { removed: true };
      });
    }

    if (command.action === "close") {
      return await sql.begin(async (tx: any) => {
        await requireOwnerCircle(tx, command.circleId, actorPersonId);
        await tx`update network.circles set status='closed',closed_at_utc=now(),version=version+1,updated_at_utc=now() where id=${command.circleId}::uuid`;
        await tx`update network.circle_member_sharing_policies set sharing_mode='none',include_period_window=false,include_phase_context=false,include_wellbeing_context=false,revoked_at_utc=now(),version=version+1,updated_at_utc=now() where circle_id=${command.circleId}::uuid`;
        await audit(
          tx,
          command.circleId,
          actorPersonId,
          "circle.closed",
          actorPersonId,
        );
        return { closed: true };
      });
    }

    throw invalid("unsupported_circle_command");
  }

  return { list, listIncomingInvitations, execute };
}

async function mapCircle(
  connection: any,
  circle: Row,
  viewerPersonId: string,
): Promise<Record<string, unknown>> {
  const members = await connection`
    select m.person_id::text,m.membership_role,m.membership_status,p.display_name
    from network.circle_members m
    left join core.person_profiles p on p.person_id=m.person_id
    where m.circle_id=${circle.id}::uuid and m.membership_status='active'
    order by case when m.membership_role='owner' then 0 else 1 end,p.display_name nulls last,m.created_at_utc
  `;
  const policies = await connection`
    select * from network.circle_member_sharing_policies
    where circle_id=${circle.id}::uuid
  `;
  const policyByPerson = new Map(
    policies.map((row: Row) => [String(row.person_id), row]),
  );
  const contributions = [];
  for (const member of members) {
    const memberPersonId = String(member.person_id);
    const raw = policyByPerson.get(memberPersonId) as Row | undefined;
    const policy = normalizeCircleSharingPolicy({
      mode: raw?.sharing_mode ?? "none",
      includePeriodWindow: raw?.include_period_window === true,
      includePhaseContext: raw?.include_phase_context === true,
      includeWellbeingContext: raw?.include_wellbeing_context === true,
      revoked: raw?.revoked_at_utc != null,
    });
    const estimate = await safeEstimate(connection, memberPersonId);
    contributions.push(
      deriveCirclePlanningContribution(policy, estimate, false),
    );
  }
  const planning = aggregateCirclePlanningWindow(contributions);
  const ownPolicy = policyByPerson.get(viewerPersonId) as Row | undefined;
  return {
    id: String(circle.id),
    name: String(circle.name),
    iconKey: text(circle.icon_key),
    owner: String(circle.owner_person_id) === viewerPersonId,
    memberCount: members.length,
    members: members.map((row: Row) => ({
      personId: String(row.person_id),
      displayName: text(row.display_name) ?? "LifeMate User",
      role: String(row.membership_role),
    })),
    planningSummary: planning,
    ownSharing: ownPolicy ? mapSharing(ownPolicy) : {
      mode: "none",
      includePeriodWindow: false,
      includePhaseContext: false,
      includeWellbeingContext: false,
      version: 0,
    },
    version: Number(circle.version),
  };
}

async function safeEstimate(
  connection: any,
  personId: string,
): Promise<any | null> {
  const profiles = await connection`
    select last_period_start,cycle_length,period_length from lifemate.women_calendar_profiles
    where owner_person_id=${personId}::uuid and enabled=true limit 1
  `;
  if (!profiles[0]) return null;
  const episodes = await connection`
    select started_on from lifemate.women_calendar_episodes
    where owner_person_id=${personId}::uuid order by started_on asc limit 100
  `;
  const row = profiles[0];
  return calculateWomenCalendarEstimateFromEpisodes(
    dateString(row.last_period_start),
    Number(row.cycle_length),
    Number(row.period_length),
    episodes.map((e: Row) => dateString(e.started_on)),
  );
}

function mapSharing(row: Row): Record<string, unknown> {
  return {
    mode: String(row.sharing_mode),
    includePeriodWindow: row.include_period_window === true,
    includePhaseContext: row.include_phase_context === true,
    includeWellbeingContext: row.include_wellbeing_context === true,
    version: Number(row.version),
  };
}

function normalizeCommand(raw: Record<string, unknown>): CircleCommand {
  const action = String(raw.action ?? "").trim().toLowerCase();
  if (action === "create") {
    const name = String(raw.name ?? "").trim();
    if (name.length < 1 || name.length > 80) {
      throw invalid("invalid_circle_name");
    }
    const iconKey = text(raw.iconKey);
    if (iconKey != null && iconKey.length > 48) {
      throw invalid("invalid_circle_icon");
    }
    return { action: "create", name, iconKey };
  }
  if (action === "invite") {
    return {
      action: "invite",
      circleId: uuid(raw.circleId, "circleId"),
      inviteeAppUserId: uuid(raw.inviteeAppUserId, "inviteeAppUserId"),
    };
  }
  if (action === "respond_invite") {
    const response = String(raw.response ?? "").toLowerCase();
    if (response !== "accept" && response !== "decline") {
      throw invalid("invalid_circle_invitation_response");
    }
    return {
      action: "respond_invite",
      invitationId: uuid(raw.invitationId, "invitationId"),
      response,
    };
  }
  if (action === "set_sharing") {
    const version = raw.version == null ? undefined : Number(raw.version);
    if (version != null && (!Number.isInteger(version) || version < 0)) {
      throw invalid("invalid_circle_version");
    }
    return {
      action: "set_sharing",
      circleId: uuid(raw.circleId, "circleId"),
      mode: String(raw.mode ?? "none").toLowerCase(),
      includePeriodWindow: raw.includePeriodWindow === true,
      includePhaseContext: raw.includePhaseContext === true,
      includeWellbeingContext: raw.includeWellbeingContext === true,
      version,
    };
  }
  if (action === "leave") {
    return { action: "leave", circleId: uuid(raw.circleId, "circleId") };
  }
  if (action === "remove_member") {
    return {
      action: "remove_member",
      circleId: uuid(raw.circleId, "circleId"),
      memberPersonId: uuid(raw.memberPersonId, "memberPersonId"),
    };
  }
  if (action === "close") {
    return { action: "close", circleId: uuid(raw.circleId, "circleId") };
  }
  throw invalid("unsupported_circle_command");
}

async function requireOwnerCircle(
  connection: any,
  circleId: string,
  personId: string,
): Promise<Row> {
  const rows =
    await connection`select * from network.circles where id=${circleId}::uuid and owner_person_id=${personId}::uuid and status='active' for update`;
  if (!rows[0]) throw notFound();
  return rows[0];
}

async function requireActiveMember(
  connection: any,
  circleId: string,
  personId: string,
): Promise<void> {
  const rows =
    await connection`select 1 from network.circle_members m join network.circles c on c.id=m.circle_id where m.circle_id=${circleId}::uuid and m.person_id=${personId}::uuid and m.membership_status='active' and c.status='active' limit 1`;
  if (!rows[0]) throw notFound();
}

async function selfPersonId(
  connection: any,
  appUserId: string,
): Promise<string> {
  const rows =
    await connection`select core.self_person_id_for_legacy_app_user(${appUserId}::uuid)::text as person_id`;
  const value = rows[0]?.person_id;
  if (typeof value !== "string" || value.length === 0) {
    throw new ApiError(
      409,
      "identity_person_mapping_missing",
      "The LifeMate person mapping is unavailable.",
    );
  }
  return value;
}

async function audit(
  connection: any,
  circleId: string,
  actorPersonId: string,
  action: string,
  subjectPersonId: string,
): Promise<void> {
  await connection`insert into network.circle_audit_events(id,circle_id,actor_person_id,action,subject_person_id,metadata_json,created_at_utc) values(${crypto.randomUUID()}::uuid,${circleId}::uuid,${actorPersonId}::uuid,${action},${subjectPersonId}::uuid,null,now())`;
}

function uuid(value: unknown, field: string): string {
  const textValue = String(value ?? "").trim();
  if (
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
      .test(textValue)
  ) throw invalid(`invalid_${field}`);
  return textValue;
}
function text(value: unknown): string | null {
  const v = value == null ? "" : String(value).trim();
  return v.length === 0 ? null : v;
}
function iso(value: unknown): string | null {
  if (value == null) return null;
  const d = value instanceof Date ? value : new Date(String(value));
  return Number.isFinite(d.getTime()) ? d.toISOString() : null;
}
function dateString(value: unknown): string {
  if (value instanceof Date) return value.toISOString().slice(0, 10);
  return String(value).slice(0, 10);
}
function invalid(code: string): ApiError {
  return new ApiError(400, code, "Invalid Women Health Circle request.");
}
function notFound(): ApiError {
  return new ApiError(
    404,
    "women_circle_not_found",
    "Women Health Circle was not found or is not accessible.",
  );
}

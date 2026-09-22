import { getAdminSql } from "./database_client.ts";
import type {
  AdminCircleKind,
  AdminCircleStatus,
} from "./circle_directory.ts";

type Row = Record<string, unknown>;

export type AdminCircleListQuery = {
  page: number;
  pageSize: number;
  status?: AdminCircleStatus;
  kind?: AdminCircleKind;
  ownerPersonId?: string;
  memberPersonId?: string;
  q?: string;
};

function nullableText(value: unknown): string | null {
  return typeof value === "string" ? value : null;
}

function text(value: unknown): string {
  return typeof value === "string" ? value : "";
}

function integer(value: unknown): number {
  const number = Number(value);
  return Number.isInteger(number) ? number : 0;
}

function iso(value: unknown): string | null {
  if (value == null) return null;
  return value instanceof Date ? value.toISOString() : String(value);
}

export function createAdminCircleDirectoryStore(databaseUrl: string) {
  const sql = getAdminSql(databaseUrl);

  async function list(query: AdminCircleListQuery) {
    const offset = (query.page - 1) * query.pageSize;
    const status = query.status ?? null;
    const kind = query.kind ?? null;
    const ownerPersonId = query.ownerPersonId ?? null;
    const memberPersonId = query.memberPersonId ?? null;
    const search = query.q ? `%${query.q}%` : null;
    const [rows, totals] = await Promise.all([
      sql`
        select
          c.id,c.owner_person_id,c.circle_kind,c.name,c.icon_key,c.status,c.version,
          c.created_at_utc,c.updated_at_utc,c.closed_at_utc,
          owner_profile.display_name as owner_display_name,
          count(distinct m.id) filter (where m.membership_status='active')::integer as active_member_count,
          count(distinct i.id) filter (where i.status='pending')::integer as pending_invitation_count
        from network.circles c
        left join core.person_profiles owner_profile on owner_profile.person_id=c.owner_person_id
        left join network.circle_members m on m.circle_id=c.id
        left join network.circle_invitations i on i.circle_id=c.id
        where (${status}::text is null or c.status=${status})
          and (${kind}::text is null or c.circle_kind=${kind})
          and (${ownerPersonId}::uuid is null or c.owner_person_id=${ownerPersonId}::uuid)
          and (
            ${memberPersonId}::uuid is null
            or exists(
              select 1
              from network.circle_members member_filter
              where member_filter.circle_id=c.id
                and member_filter.person_id=${memberPersonId}::uuid
                and member_filter.membership_status='active'
            )
          )
          and (
            ${search}::text is null
            or c.name ilike ${search}
            or owner_profile.display_name ilike ${search}
          )
        group by c.id,owner_profile.display_name
        order by c.updated_at_utc desc,c.id desc
        limit ${query.pageSize} offset ${offset}
      `,
      sql`
        select count(*)::integer as total
        from network.circles c
        left join core.person_profiles owner_profile on owner_profile.person_id=c.owner_person_id
        where (${status}::text is null or c.status=${status})
          and (${kind}::text is null or c.circle_kind=${kind})
          and (${ownerPersonId}::uuid is null or c.owner_person_id=${ownerPersonId}::uuid)
          and (
            ${memberPersonId}::uuid is null
            or exists(
              select 1
              from network.circle_members member_filter
              where member_filter.circle_id=c.id
                and member_filter.person_id=${memberPersonId}::uuid
                and member_filter.membership_status='active'
            )
          )
          and (
            ${search}::text is null
            or c.name ilike ${search}
            or owner_profile.display_name ilike ${search}
          )
      `,
    ]);

    return {
      page: query.page,
      pageSize: query.pageSize,
      total: integer(totals[0]?.total),
      items: (rows as unknown as Row[]).map((row) => ({
        circleId: text(row.id),
        ownerPersonId: text(row.owner_person_id),
        ownerDisplayName: nullableText(row.owner_display_name),
        kind: text(row.circle_kind),
        name: text(row.name),
        iconKey: nullableText(row.icon_key),
        status: text(row.status),
        version: integer(row.version),
        activeMemberCount: integer(row.active_member_count),
        pendingInvitationCount: integer(row.pending_invitation_count),
        createdAtUtc: iso(row.created_at_utc),
        updatedAtUtc: iso(row.updated_at_utc),
        closedAtUtc: iso(row.closed_at_utc),
      })),
    };
  }

  async function detail(circleId: string) {
    const circleRows = await sql`
      select
        c.id,c.owner_person_id,c.circle_kind,c.name,c.icon_key,c.status,c.version,
        c.created_at_utc,c.updated_at_utc,c.closed_at_utc,
        owner_profile.display_name as owner_display_name
      from network.circles c
      left join core.person_profiles owner_profile on owner_profile.person_id=c.owner_person_id
      where c.id=${circleId}::uuid
      limit 1
    `;
    if (circleRows.length === 0) return null;

    const [memberRows, invitationRows] = await Promise.all([
      sql`
        select
          m.id,m.person_id,m.membership_role,m.membership_status,
          m.joined_at_utc,m.left_at_utc,m.removed_at_utc,m.created_at_utc,m.updated_at_utc,
          p.display_name,
          sp.sharing_mode,sp.version as sharing_version,sp.revoked_at_utc as sharing_revoked_at_utc
        from network.circle_members m
        left join core.person_profiles p on p.person_id=m.person_id
        left join network.circle_member_sharing_policies sp
          on sp.circle_id=m.circle_id and sp.person_id=m.person_id
        where m.circle_id=${circleId}::uuid
        order by
          case when m.membership_role='owner' then 0 else 1 end,
          m.created_at_utc asc,m.id asc
      `,
      sql`
        select
          i.id,i.inviter_person_id,i.invitee_person_id,i.status,i.expires_at_utc,
          i.accepted_at_utc,i.declined_at_utc,i.revoked_at_utc,i.created_at_utc,i.updated_at_utc,
          inviter.display_name as inviter_display_name,
          invitee.display_name as invitee_display_name,
          case when i.invitee_person_id is null then 'contact' else 'person' end as target_kind
        from network.circle_invitations i
        left join core.person_profiles inviter on inviter.person_id=i.inviter_person_id
        left join core.person_profiles invitee on invitee.person_id=i.invitee_person_id
        where i.circle_id=${circleId}::uuid
        order by i.created_at_utc desc,i.id desc
      `,
    ]);

    const circle = circleRows[0] as unknown as Row;
    return {
      circle: {
        circleId: text(circle.id),
        ownerPersonId: text(circle.owner_person_id),
        ownerDisplayName: nullableText(circle.owner_display_name),
        kind: text(circle.circle_kind),
        name: text(circle.name),
        iconKey: nullableText(circle.icon_key),
        status: text(circle.status),
        version: integer(circle.version),
        createdAtUtc: iso(circle.created_at_utc),
        updatedAtUtc: iso(circle.updated_at_utc),
        closedAtUtc: iso(circle.closed_at_utc),
      },
      members: (memberRows as unknown as Row[]).map((row) => ({
        membershipId: text(row.id),
        personId: text(row.person_id),
        displayName: nullableText(row.display_name),
        role: text(row.membership_role),
        status: text(row.membership_status),
        sharingMode: nullableText(row.sharing_mode) ?? "none",
        sharingVersion: row.sharing_version == null
          ? null
          : integer(row.sharing_version),
        joinedAtUtc: iso(row.joined_at_utc),
        leftAtUtc: iso(row.left_at_utc),
        removedAtUtc: iso(row.removed_at_utc),
        sharingRevokedAtUtc: iso(row.sharing_revoked_at_utc),
        updatedAtUtc: iso(row.updated_at_utc),
      })),
      invitations: (invitationRows as unknown as Row[]).map((row) => ({
        invitationId: text(row.id),
        inviterPersonId: text(row.inviter_person_id),
        inviterDisplayName: nullableText(row.inviter_display_name),
        inviteePersonId: nullableText(row.invitee_person_id),
        inviteeDisplayName: nullableText(row.invitee_display_name),
        targetKind: text(row.target_kind),
        status: text(row.status),
        expiresAtUtc: iso(row.expires_at_utc),
        acceptedAtUtc: iso(row.accepted_at_utc),
        declinedAtUtc: iso(row.declined_at_utc),
        revokedAtUtc: iso(row.revoked_at_utc),
        createdAtUtc: iso(row.created_at_utc),
        updatedAtUtc: iso(row.updated_at_utc),
      })),
    };
  }

  return { list, detail };
}

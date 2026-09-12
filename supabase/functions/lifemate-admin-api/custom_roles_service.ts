import { getAdminSql } from "./database_client.ts";
import {
  type CustomRoleMutationAction,
  type CustomRoleMutationRequest,
  type CustomRolePermissionAction,
  type CustomRolePermissionRequest,
} from "./custom_roles.ts";
import { ApiError } from "./validation.ts";

type Row = Record<string, unknown>;

function result(value: unknown): Row {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new ApiError(
      503,
      "custom_role_workflow_unavailable",
      "Custom role workflow result was unavailable.",
    );
  }
  const row = value as Row;
  if (
    !Number.isInteger(row.httpStatus) || typeof row.code !== "string" ||
    typeof row.replayed !== "boolean"
  ) {
    throw new ApiError(
      503,
      "custom_role_workflow_unavailable",
      "Custom role workflow result was invalid.",
    );
  }
  return row;
}

export function createCustomRoleStore(databaseUrl: string) {
  const sql = getAdminSql(databaseUrl);
  return {
    async list(actorAccountId: string) {
      const roles = await sql`
        select r.code,r.display_name,r.rank,r.status,r.version,r.created_at_utc,r.updated_at_utc,
          coalesce(array_agg(distinct rp.permission_code order by rp.permission_code) filter (where rp.permission_code is not null),array[]::varchar[]) as permissions,
          count(distinct mr.account_id) filter (where mr.revoked_at_utc is null and mr.starts_at_utc<=now() and (mr.expires_at_utc is null or mr.expires_at_utc>now()))::integer as active_member_count
        from admin.roles r
        left join admin.role_permissions rp on rp.role_id=r.id
        left join admin.member_roles mr on mr.role_id=r.id
        where r.is_system=false
        group by r.id
        order by r.rank,r.code
      `;
      const catalog = await sql`
        select p.code,p.domain,p.risk_level,p.description,
          admin.account_has_permission(${actorAccountId}::uuid,p.code) as delegable
        from admin.permissions p
        where p.role_assignable=true and p.risk_level<>'ELEVATED'
        order by p.domain,p.code
      `;
      return {
        roles: roles.map((row) => ({
          code: String(row.code),
          displayName: String(row.display_name),
          rank: Number(row.rank),
          status: String(row.status),
          version: Number(row.version),
          permissions: Array.isArray(row.permissions)
            ? row.permissions.map(String)
            : [],
          activeMemberCount: Number(row.active_member_count ?? 0),
          createdAtUtc: new Date(String(row.created_at_utc)).toISOString(),
          updatedAtUtc: new Date(String(row.updated_at_utc)).toISOString(),
        })),
        permissionCatalog: catalog.map((row) => ({
          code: String(row.code),
          domain: String(row.domain),
          riskLevel: String(row.risk_level),
          description: String(row.description),
          delegable: Boolean(row.delegable),
        })),
      };
    },

    async mutateRole(input: {
      actorAccountId: string;
      action: CustomRoleMutationAction;
      payload: CustomRoleMutationRequest;
      correlationId: string;
      idempotencyKey: string;
      requestHash: string;
    }) {
      const rows = await sql`
        select admin.mutate_custom_role(
          ${input.actorAccountId}::uuid,
          ${input.action}::character varying,
          ${input.payload.code}::character varying,
          ${input.payload.displayName}::character varying,
          ${input.payload.rank}::smallint,
          ${input.payload.expectedVersion}::bigint,
          ${input.payload.reason}::character varying,
          ${input.correlationId}::uuid,
          ${input.idempotencyKey}::character varying,
          ${input.requestHash}::character varying
        ) as result
      `;
      return result(rows[0]?.result);
    },

    async mutatePermission(input: {
      actorAccountId: string;
      roleCode: string;
      action: CustomRolePermissionAction;
      payload: CustomRolePermissionRequest;
      correlationId: string;
      idempotencyKey: string;
      requestHash: string;
    }) {
      const rows = await sql`
        select admin.mutate_custom_role_permission(
          ${input.actorAccountId}::uuid,
          ${input.roleCode}::character varying,
          ${input.payload.permissionCode}::character varying,
          ${input.action}::character varying,
          ${input.payload.expectedVersion}::bigint,
          ${input.payload.reason}::character varying,
          ${input.correlationId}::uuid,
          ${input.idempotencyKey}::character varying,
          ${input.requestHash}::character varying
        ) as result
      `;
      return result(rows[0]?.result);
    },
  };
}

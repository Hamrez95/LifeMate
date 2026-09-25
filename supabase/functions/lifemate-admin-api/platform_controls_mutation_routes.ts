import {
  type AdminCapabilitySnapshot,
  requirePermission,
} from "./authorization.ts";
import { getAdminSql } from "./database_client.ts";
import { json } from "./http.ts";
import { parseControlKey } from "./platform_controls.ts";
import {
  matchRuleId,
  parseControlCreate,
  parseControlUpdate,
  parseKillSwitchMutation,
  parseRollbackMutation,
  parseRuleMutation,
  platformRequestHash,
} from "./platform_controls_admin.ts";
import { ApiError, requireIdempotencyKey } from "./validation.ts";

type Context = {
  request: Request;
  path: string;
  accountId: string;
  admin: AdminCapabilitySnapshot;
  correlationId: string;
  origin: string | null;
};

type StoredIdempotency = {
  request_hash?: unknown;
  status?: unknown;
  response_status?: unknown;
  response_json?: unknown;
};

function replay(
  existing: StoredIdempotency | undefined,
  requestHash: string,
): { status: number; body: Record<string, unknown> } | null {
  if (!existing) return null;
  if (String(existing.request_hash) !== requestHash) {
    throw new ApiError(
      409,
      "idempotency_conflict",
      "This Idempotency-Key was already used for a different request.",
    );
  }
  if (existing.status !== "Completed" || !existing.response_json) {
    throw new ApiError(
      409,
      "idempotency_in_progress",
      "This request is already being processed.",
    );
  }
  return {
    status: Number(existing.response_status ?? 200),
    body: {
      ...(existing.response_json as Record<string, unknown>),
      replayed: true,
    },
  };
}

function controlKeyFrom(path: string, suffix = ""): string | null {
  const escaped = suffix.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const match = path.match(
    new RegExp(`^/api/v1/platform/controls/([^/]+)${escaped}$`),
  );
  return match ? parseControlKey(decodeURIComponent(match[1])) : null;
}

export function createPlatformControlMutationRouteHandler(
  databaseUrl: string,
  invalidate: (key?: string) => void,
) {
  const sql = getAdminSql(databaseUrl);

  return async function handlePlatformControlMutation(
    input: Context,
  ): Promise<Response | null> {
    const { request, path, accountId, admin, correlationId, origin } = input;

    if (request.method === "POST" && path === "/api/v1/platform/controls") {
      requirePermission(admin, "platform.config.write");
      const idempotencyKey = requireIdempotencyKey(request);
      const payload = await parseControlCreate(request);
      const operation = "platform.control.create";
      const hash = await platformRequestHash(operation, payload);
      const result = await sql.begin(async (tx) => {
        await tx`select pg_advisory_xact_lock(hashtextextended(${
          accountId + ":" + operation + ":" + idempotencyKey
        },0))`;
        const existing = await tx`
          select request_hash,status,response_status,response_json
          from admin.idempotency_keys
          where actor_account_id=${accountId}::uuid and operation=${operation}
            and idempotency_key=${idempotencyKey} limit 1
        `;
        const prior = replay(
          existing[0] as StoredIdempotency | undefined,
          hash,
        );
        if (prior) return prior;
        await tx`
          insert into admin.idempotency_keys(actor_account_id,operation,idempotency_key,request_hash,status,expires_at_utc)
          values (${accountId}::uuid,${operation},${idempotencyKey},${hash},'Processing',now()+interval '24 hours')
        `;
        const created = await tx`
          insert into platform.controls(
            control_key,control_kind,value_type,default_value,description,fail_closed,status,version
          ) values (
            ${payload.controlKey},${payload.controlKind},${payload.valueType},${
          JSON.stringify(payload.defaultValue)
        }::jsonb,
            ${payload.description},${payload.failClosed},'Active',1
          )
          returning control_key,control_kind,value_type,default_value,description,fail_closed,status,version,created_at_utc,updated_at_utc
        `;
        const body = { item: created[0], replayed: false };
        await tx`
          insert into admin.audit_events(actor_account_id,action,resource_type,resource_id,result,reason,correlation_id,request_id,elevated_access,metadata_json)
          values (${accountId}::uuid,'platform.control.create','platform_control',${payload.controlKey},'Succeeded',${payload.reason},${correlationId}::uuid,${idempotencyKey},false,
            jsonb_build_object('kind',${payload.controlKind},'valueType',${payload.valueType},'failClosed',${payload.failClosed}))
        `;
        await tx`
          update admin.idempotency_keys set status='Completed',response_status=201,
            response_json=${JSON.stringify(body)}::jsonb,updated_at_utc=now()
          where actor_account_id=${accountId}::uuid and operation=${operation} and idempotency_key=${idempotencyKey}
        `;
        return { status: 201, body };
      });
      invalidate(payload.controlKey);
      return json(result.body, result.status, origin);
    }

    const directKey = controlKeyFrom(path);
    if (request.method === "PATCH" && directKey) {
      requirePermission(admin, "platform.config.write");
      const typeRows =
        await sql`select value_type from platform.controls where control_key=${directKey} limit 1`;
      if (!typeRows[0]) {
        throw new ApiError(
          404,
          "platform_control_not_found",
          "Platform control was not found.",
        );
      }
      const payload = await parseControlUpdate(
        request,
        String(typeRows[0].value_type) as
          | "Boolean"
          | "Integer"
          | "String"
          | "Json",
      );
      const idempotencyKey = requireIdempotencyKey(request);
      const operation = "platform.control.update";
      const hash = await platformRequestHash(operation, {
        key: directKey,
        ...payload,
      });
      const result = await sql.begin(async (tx) => {
        await tx`select pg_advisory_xact_lock(hashtextextended(${
          accountId + ":" + operation + ":" + idempotencyKey
        },0))`;
        const existing =
          await tx`select request_hash,status,response_status,response_json from admin.idempotency_keys where actor_account_id=${accountId}::uuid and operation=${operation} and idempotency_key=${idempotencyKey} limit 1`;
        const prior = replay(
          existing[0] as StoredIdempotency | undefined,
          hash,
        );
        if (prior) return prior;
        await tx`insert into admin.idempotency_keys(actor_account_id,operation,idempotency_key,request_hash,status,expires_at_utc) values (${accountId}::uuid,${operation},${idempotencyKey},${hash},'Processing',now()+interval '24 hours')`;
        const current =
          await tx`select control_kind,value_type,version,status from platform.controls where control_key=${directKey} for update`;
        if (!current[0]) {
          throw new ApiError(
            404,
            "platform_control_not_found",
            "Platform control was not found.",
          );
        }
        if (Number(current[0].version) !== payload.expectedVersion) {
          throw new ApiError(
            409,
            "platform_control_version_conflict",
            "Platform control was changed by another operation.",
          );
        }
        const updated = await tx`
          update platform.controls set default_value=${
          JSON.stringify(payload.defaultValue)
        }::jsonb,
            description=${payload.description},fail_closed=${payload.failClosed},status=${payload.status},
            version=version+1,updated_at_utc=now()
          where control_key=${directKey}
          returning control_key,control_kind,value_type,default_value,description,fail_closed,status,version,updated_at_utc
        `;
        const body = { item: updated[0], replayed: false };
        await tx`insert into admin.audit_events(actor_account_id,action,resource_type,resource_id,result,reason,correlation_id,request_id,elevated_access,metadata_json) values (${accountId}::uuid,'platform.control.update','platform_control',${directKey},'Succeeded',${payload.reason},${correlationId}::uuid,${idempotencyKey},false,jsonb_build_object('previousVersion',${payload.expectedVersion},'version',${
          Number(updated[0].version)
        },'status',${payload.status}))`;
        await tx`update admin.idempotency_keys set status='Completed',response_status=200,response_json=${
          JSON.stringify(body)
        }::jsonb,updated_at_utc=now() where actor_account_id=${accountId}::uuid and operation=${operation} and idempotency_key=${idempotencyKey}`;
        return { status: 200, body };
      });
      invalidate(directKey);
      return json(result.body, result.status, origin);
    }

    const rulesKey = controlKeyFrom(path, "/rules");
    if (request.method === "POST" && rulesKey) {
      requirePermission(admin, "platform.config.write");
      const controlRows =
        await sql`select value_type,status from platform.controls where control_key=${rulesKey} limit 1`;
      if (!controlRows[0]) {
        throw new ApiError(
          404,
          "platform_control_not_found",
          "Platform control was not found.",
        );
      }
      if (controlRows[0].status !== "Active") {
        throw new ApiError(
          409,
          "platform_control_inactive",
          "Rules cannot be added to a retired control.",
        );
      }
      const payload = await parseRuleMutation(
        request,
        String(controlRows[0].value_type) as
          | "Boolean"
          | "Integer"
          | "String"
          | "Json",
        true,
      );
      const idempotencyKey = requireIdempotencyKey(request);
      const operation = "platform.control_rule.create";
      const hash = await platformRequestHash(operation, {
        controlKey: rulesKey,
        ...payload,
      });
      const result = await sql.begin(async (tx) => {
        await tx`select pg_advisory_xact_lock(hashtextextended(${
          accountId + ":" + operation + ":" + idempotencyKey
        },0))`;
        const existing =
          await tx`select request_hash,status,response_status,response_json from admin.idempotency_keys where actor_account_id=${accountId}::uuid and operation=${operation} and idempotency_key=${idempotencyKey} limit 1`;
        const prior = replay(
          existing[0] as StoredIdempotency | undefined,
          hash,
        );
        if (prior) return prior;
        await tx`insert into admin.idempotency_keys(actor_account_id,operation,idempotency_key,request_hash,status,expires_at_utc) values (${accountId}::uuid,${operation},${idempotencyKey},${hash},'Processing',now()+interval '24 hours')`;
        const created = await tx`
          insert into platform.control_rules(control_key,priority,target_type,target_key,rollout_basis_points,value,starts_at_utc,ends_at_utc,status,version)
          values (${rulesKey},${payload.priority},${payload.targetType},${payload.targetKey},${payload.rolloutBasisPoints},${
          JSON.stringify(payload.value)
        }::jsonb,${payload.startsAtUtc}::timestamptz,${payload.endsAtUtc}::timestamptz,${payload.status},1)
          returning id,control_key,priority,target_type,target_key,rollout_basis_points,value,starts_at_utc,ends_at_utc,status,version,created_at_utc,updated_at_utc
        `;
        const body = { item: created[0], replayed: false };
        await tx`insert into admin.audit_events(actor_account_id,action,resource_type,resource_id,result,reason,correlation_id,request_id,elevated_access,metadata_json) values (${accountId}::uuid,'platform.control_rule.create','platform_control_rule',${
          String(created[0].id)
        },'Succeeded',${payload.reason},${correlationId}::uuid,${idempotencyKey},false,jsonb_build_object('controlKey',${rulesKey},'targetType',${payload.targetType},'priority',${payload.priority}))`;
        await tx`update admin.idempotency_keys set status='Completed',response_status=201,response_json=${
          JSON.stringify(body)
        }::jsonb,updated_at_utc=now() where actor_account_id=${accountId}::uuid and operation=${operation} and idempotency_key=${idempotencyKey}`;
        return { status: 201, body };
      });
      invalidate(rulesKey);
      return json(result.body, result.status, origin);
    }

    const ruleId = matchRuleId(path);
    if (request.method === "PATCH" && ruleId) {
      requirePermission(admin, "platform.config.write");
      const ruleRows = await sql`
        select r.control_key,c.value_type from platform.control_rules r
        join platform.controls c on c.control_key=r.control_key
        where r.id=${ruleId}::uuid limit 1
      `;
      if (!ruleRows[0]) {
        throw new ApiError(
          404,
          "platform_rule_not_found",
          "Control rule was not found.",
        );
      }
      const controlKey = String(ruleRows[0].control_key);
      const payload = await parseRuleMutation(
        request,
        String(ruleRows[0].value_type) as
          | "Boolean"
          | "Integer"
          | "String"
          | "Json",
        false,
      );
      const idempotencyKey = requireIdempotencyKey(request);
      const operation = "platform.control_rule.update";
      const hash = await platformRequestHash(operation, { ruleId, ...payload });
      const result = await sql.begin(async (tx) => {
        await tx`select pg_advisory_xact_lock(hashtextextended(${
          accountId + ":" + operation + ":" + idempotencyKey
        },0))`;
        const existing =
          await tx`select request_hash,status,response_status,response_json from admin.idempotency_keys where actor_account_id=${accountId}::uuid and operation=${operation} and idempotency_key=${idempotencyKey} limit 1`;
        const prior = replay(
          existing[0] as StoredIdempotency | undefined,
          hash,
        );
        if (prior) return prior;
        await tx`insert into admin.idempotency_keys(actor_account_id,operation,idempotency_key,request_hash,status,expires_at_utc) values (${accountId}::uuid,${operation},${idempotencyKey},${hash},'Processing',now()+interval '24 hours')`;
        const current =
          await tx`select version from platform.control_rules where id=${ruleId}::uuid for update`;
        if (!current[0]) {
          throw new ApiError(
            404,
            "platform_rule_not_found",
            "Control rule was not found.",
          );
        }
        if (Number(current[0].version) !== payload.expectedVersion) {
          throw new ApiError(
            409,
            "platform_rule_version_conflict",
            "Control rule was changed by another operation.",
          );
        }
        const updated = await tx`
          update platform.control_rules set priority=${payload.priority},target_type=${payload.targetType},target_key=${payload.targetKey},
            rollout_basis_points=${payload.rolloutBasisPoints},value=${
          JSON.stringify(payload.value)
        }::jsonb,
            starts_at_utc=${payload.startsAtUtc}::timestamptz,ends_at_utc=${payload.endsAtUtc}::timestamptz,
            status=${payload.status},version=version+1,updated_at_utc=now()
          where id=${ruleId}::uuid
          returning id,control_key,priority,target_type,target_key,rollout_basis_points,value,starts_at_utc,ends_at_utc,status,version,updated_at_utc
        `;
        const body = { item: updated[0], replayed: false };
        await tx`insert into admin.audit_events(actor_account_id,action,resource_type,resource_id,result,reason,correlation_id,request_id,elevated_access,metadata_json) values (${accountId}::uuid,'platform.control_rule.update','platform_control_rule',${ruleId},'Succeeded',${payload.reason},${correlationId}::uuid,${idempotencyKey},false,jsonb_build_object('controlKey',${controlKey},'previousVersion',${payload.expectedVersion},'version',${
          Number(updated[0].version)
        }))`;
        await tx`update admin.idempotency_keys set status='Completed',response_status=200,response_json=${
          JSON.stringify(body)
        }::jsonb,updated_at_utc=now() where actor_account_id=${accountId}::uuid and operation=${operation} and idempotency_key=${idempotencyKey}`;
        return { status: 200, body };
      });
      invalidate(controlKey);
      return json(result.body, result.status, origin);
    }

    const historyKey = controlKeyFrom(path, "/history");
    if (request.method === "GET" && historyKey) {
      requirePermission(admin, "platform.config.read");
      const controlHistory =
        await sql`select version,snapshot_json,archived_at_utc from platform.control_history where control_key=${historyKey} order by version desc limit 100`;
      const ruleHistory =
        await sql`select rule_id,version,snapshot_json,archived_at_utc from platform.control_rule_history where control_key=${historyKey} order by archived_at_utc desc,rule_id limit 200`;
      return json(
        {
          controlKey: historyKey,
          controlHistory,
          ruleHistory,
          freshness: { status: "fresh", asOfUtc: new Date().toISOString() },
        },
        200,
        origin,
      );
    }

    const actionMatch = path.match(
      /^\/api\/v1\/platform\/controls\/([^/]+)\/actions\/(rollback|kill-switch)$/,
    );
    if (request.method === "POST" && actionMatch) {
      requirePermission(admin, "platform.config.write");
      const key = parseControlKey(decodeURIComponent(actionMatch[1]));
      const action = actionMatch[2];
      const idempotencyKey = requireIdempotencyKey(request);
      const operation = `platform.control.${action}`;
      const payload = action === "rollback"
        ? await parseRollbackMutation(request)
        : await parseKillSwitchMutation(request);
      const hash = await platformRequestHash(operation, { key, ...payload });
      const result = await sql.begin(async (tx) => {
        await tx`select pg_advisory_xact_lock(hashtextextended(${
          accountId + ":" + operation + ":" + idempotencyKey
        },0))`;
        const existing =
          await tx`select request_hash,status,response_status,response_json from admin.idempotency_keys where actor_account_id=${accountId}::uuid and operation=${operation} and idempotency_key=${idempotencyKey} limit 1`;
        const prior = replay(
          existing[0] as StoredIdempotency | undefined,
          hash,
        );
        if (prior) return prior;
        await tx`insert into admin.idempotency_keys(actor_account_id,operation,idempotency_key,request_hash,status,expires_at_utc) values (${accountId}::uuid,${operation},${idempotencyKey},${hash},'Processing',now()+interval '24 hours')`;
        const current =
          await tx`select control_kind,value_type,version from platform.controls where control_key=${key} for update`;
        if (!current[0]) {
          throw new ApiError(
            404,
            "platform_control_not_found",
            "Platform control was not found.",
          );
        }
        if (Number(current[0].version) !== payload.expectedVersion) {
          throw new ApiError(
            409,
            "platform_control_version_conflict",
            "Platform control was changed by another operation.",
          );
        }
        let updated;
        if (action === "kill-switch") {
          if (
            current[0].control_kind !== "FeatureFlag" ||
            current[0].value_type !== "Boolean"
          ) {
            throw new ApiError(
              409,
              "platform_kill_switch_invalid",
              "Kill switch applies only to Boolean FeatureFlag controls.",
            );
          }
          await tx`update platform.control_rules set status='Disabled',version=version+1,updated_at_utc=now() where control_key=${key} and status='Active'`;
          updated =
            await tx`update platform.controls set default_value='false'::jsonb,fail_closed=true,version=version+1,updated_at_utc=now() where control_key=${key} returning control_key,control_kind,value_type,default_value,description,fail_closed,status,version,updated_at_utc`;
        } else {
          const rollback = payload as Awaited<
            ReturnType<typeof parseRollbackMutation>
          >;
          const history =
            await tx`select snapshot_json from platform.control_history where control_key=${key} and version=${rollback.historyVersion} limit 1`;
          if (!history[0]) {
            throw new ApiError(
              404,
              "platform_history_not_found",
              "Requested control history version was not found.",
            );
          }
          const snapshot = history[0].snapshot_json as Record<string, unknown>;
          if (
            String(snapshot.control_kind) !== String(current[0].control_kind) ||
            String(snapshot.value_type) !== String(current[0].value_type)
          ) {
            throw new ApiError(
              409,
              "platform_history_incompatible",
              "Historical control type is incompatible.",
            );
          }
          updated = await tx`
            update platform.controls set default_value=${
            JSON.stringify(snapshot.default_value)
          }::jsonb,
              description=${String(snapshot.description)},fail_closed=${
            Boolean(snapshot.fail_closed)
          },
              status=${
            String(snapshot.status)
          },version=version+1,updated_at_utc=now()
            where control_key=${key}
            returning control_key,control_kind,value_type,default_value,description,fail_closed,status,version,updated_at_utc
          `;
        }
        const body = { item: updated[0], replayed: false };
        await tx`insert into admin.audit_events(actor_account_id,action,resource_type,resource_id,result,reason,correlation_id,request_id,elevated_access,metadata_json) values (${accountId}::uuid,${operation},'platform_control',${key},'Succeeded',${payload.reason},${correlationId}::uuid,${idempotencyKey},false,jsonb_build_object('previousVersion',${payload.expectedVersion},'version',${
          Number(updated[0].version)
        }))`;
        await tx`update admin.idempotency_keys set status='Completed',response_status=200,response_json=${
          JSON.stringify(body)
        }::jsonb,updated_at_utc=now() where actor_account_id=${accountId}::uuid and operation=${operation} and idempotency_key=${idempotencyKey}`;
        return { status: 200, body };
      });
      invalidate(key);
      return json(result.body, result.status, origin);
    }

    return null;
  };
}

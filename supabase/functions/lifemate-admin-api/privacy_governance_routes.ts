import {
  type AdminCapabilitySnapshot,
  requirePermission,
} from "./authorization.ts";
import { getAdminSql } from "./database_client.ts";
import { json } from "./http.ts";
import {
  matchLegalDocumentActionPath,
  matchPreferencePurposePath,
  parseLegalDocumentCreate,
  parseLegalDocumentStatusMutation,
  parsePreferencePurposeMutation,
  requestHash,
} from "./privacy_governance.ts";
import { ApiError, requireIdempotencyKey } from "./validation.ts";

export type PrivacyGovernanceRouteContext = {
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

function limitFrom(url: URL): number {
  const raw = url.searchParams.get("limit");
  if (raw === null) return 100;
  const value = Number(raw);
  if (!Number.isInteger(value) || value < 1 || value > 200) {
    throw new ApiError(400, "limit_invalid", "limit must be between 1 and 200.");
  }
  return value;
}

function replayedIdempotentResult(
  existing: StoredIdempotency | undefined,
  hash: string,
): { status: number; body: Record<string, unknown> } | null {
  if (!existing) return null;
  if (String(existing.request_hash) !== hash) {
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
  const original = existing.response_json as Record<string, unknown>;
  return {
    status: Number(existing.response_status ?? 200),
    body: { ...original, replayed: true },
  };
}

export function createPrivacyGovernanceRouteHandler(databaseUrl: string) {
  const sql = getAdminSql(databaseUrl);

  return async function handlePrivacyGovernanceRoute(
    context: PrivacyGovernanceRouteContext,
  ): Promise<Response | null> {
    const { request, path, accountId, admin, correlationId, origin } = context;
    if (!path.startsWith("/api/v1/privacy/governance/")) return null;

    if (
      request.method === "GET" &&
      path === "/api/v1/privacy/governance/documents"
    ) {
      requirePermission(admin, "privacy.governance.read");
      const limit = limitFrom(new URL(request.url));
      const rows = await sql`
        select d.id,d.purpose,d.version,d.jurisdiction,d.title,d.document_hash,
               d.content_uri,d.status,d.effective_at_utc,d.created_at_utc,
               count(la.account_id)::integer as acceptance_count
        from consent.consent_documents d
        left join consent.legal_acceptances la
          on la.document_id=d.id and la.document_hash=d.document_hash
        where d.purpose in ('legal_terms','privacy_notice')
        group by d.id
        order by d.created_at_utc desc,d.id desc
        limit ${limit}
      `;
      return json(
        {
          items: rows,
          limit,
          freshness: { status: "fresh", asOfUtc: new Date().toISOString() },
        },
        200,
        origin,
      );
    }

    if (
      request.method === "GET" &&
      path === "/api/v1/privacy/governance/purposes"
    ) {
      requirePermission(admin, "privacy.governance.read");
      const rows = await sql`
        select purpose,category,channel,policy_version,default_enabled,user_mutable,
               status,description,created_at_utc,updated_at_utc
        from consent.preference_purposes
        order by category,purpose
      `;
      return json(
        {
          items: rows,
          freshness: { status: "fresh", asOfUtc: new Date().toISOString() },
        },
        200,
        origin,
      );
    }

    if (
      request.method === "GET" &&
      path === "/api/v1/privacy/governance/acceptance-coverage"
    ) {
      requirePermission(admin, "privacy.governance.read");
      const rows = await sql`
        select d.id as document_id,d.purpose,d.version,d.jurisdiction,d.status,
               d.effective_at_utc,
               count(la.account_id)::integer as accepted_accounts
        from consent.consent_documents d
        left join consent.legal_acceptances la
          on la.document_id=d.id and la.document_hash=d.document_hash
        where d.purpose in ('legal_terms','privacy_notice')
        group by d.id
        order by d.purpose,d.jurisdiction,d.effective_at_utc desc nulls last,d.created_at_utc desc
      `;
      return json(
        {
          items: rows,
          privacy: {
            accountIdentifiersExposed: false,
            acceptancePayloadExposed: false,
          },
          freshness: { status: "fresh", asOfUtc: new Date().toISOString() },
        },
        200,
        origin,
      );
    }

    if (
      request.method === "POST" &&
      path === "/api/v1/privacy/governance/documents"
    ) {
      requirePermission(admin, "privacy.governance.write");
      const idempotencyKey = requireIdempotencyKey(request);
      const payload = await parseLegalDocumentCreate(request);
      const operation = "privacy.document.create";
      const hash = await requestHash(operation, payload);
      const result = await sql.begin(async (tx) => {
        await tx`select pg_advisory_xact_lock(hashtextextended(${accountId + ":" + operation + ":" + idempotencyKey},0))`;
        const existing = await tx`
          select request_hash,status,response_status,response_json
          from admin.idempotency_keys
          where actor_account_id=${accountId}::uuid
            and operation=${operation}
            and idempotency_key=${idempotencyKey}
          limit 1
        `;
        const replay = replayedIdempotentResult(
          existing[0] as StoredIdempotency | undefined,
          hash,
        );
        if (replay) return replay;

        await tx`
          insert into admin.idempotency_keys(
            actor_account_id,operation,idempotency_key,request_hash,status,expires_at_utc
          ) values (
            ${accountId}::uuid,${operation},${idempotencyKey},${hash},'Processing',
            now()+interval '24 hours'
          )
        `;
        const created = await tx`
          insert into consent.consent_documents(
            id,purpose,version,jurisdiction,title,document_hash,content_uri,status,
            effective_at_utc,created_at_utc
          ) values (
            gen_random_uuid(),${payload.purpose},${payload.version},${payload.jurisdiction},
            ${payload.title},${payload.documentHash},${payload.contentUri},'Draft',
            ${payload.effectiveAtUtc}::timestamptz,now()
          )
          returning id,purpose,version,jurisdiction,title,document_hash,content_uri,
                    status,effective_at_utc,created_at_utc
        `;
        const body = { item: created[0], replayed: false };
        await tx`
          insert into admin.audit_events(
            actor_account_id,action,resource_type,resource_id,result,reason,
            correlation_id,request_id,elevated_access,metadata_json
          ) values (
            ${accountId}::uuid,'privacy.legal_document.create','consent_document',
            ${String(created[0].id)},'Succeeded',${payload.reason},
            ${correlationId}::uuid,${idempotencyKey},false,
            jsonb_build_object(
              'purpose',${payload.purpose},'version',${payload.version},
              'jurisdiction',${payload.jurisdiction},'status','Draft'
            )
          )
        `;
        await tx`
          update admin.idempotency_keys
          set status='Completed',response_status=201,
              response_json=${JSON.stringify(body)}::jsonb,updated_at_utc=now()
          where actor_account_id=${accountId}::uuid
            and operation=${operation}
            and idempotency_key=${idempotencyKey}
        `;
        return { status: 201, body };
      });
      return json(result.body, result.status, origin);
    }

    const documentAction = matchLegalDocumentActionPath(path);
    if (request.method === "POST" && documentAction) {
      requirePermission(admin, "privacy.governance.write");
      const idempotencyKey = requireIdempotencyKey(request);
      const payload = await parseLegalDocumentStatusMutation(request);
      const operation = `privacy.document.${documentAction.action}`;
      const hash = await requestHash(operation, {
        id: documentAction.id,
        ...payload,
      });
      const targetStatus = documentAction.action === "publish"
        ? "Active"
        : "Retired";
      const result = await sql.begin(async (tx) => {
        await tx`select pg_advisory_xact_lock(hashtextextended(${accountId + ":" + operation + ":" + idempotencyKey},0))`;
        const existing = await tx`
          select request_hash,status,response_status,response_json
          from admin.idempotency_keys
          where actor_account_id=${accountId}::uuid
            and operation=${operation}
            and idempotency_key=${idempotencyKey}
          limit 1
        `;
        const replay = replayedIdempotentResult(
          existing[0] as StoredIdempotency | undefined,
          hash,
        );
        if (replay) return replay;
        await tx`
          insert into admin.idempotency_keys(
            actor_account_id,operation,idempotency_key,request_hash,status,expires_at_utc
          ) values (
            ${accountId}::uuid,${operation},${idempotencyKey},${hash},'Processing',
            now()+interval '24 hours'
          )
        `;
        const previous = await tx`
          select id,purpose,version,jurisdiction,title,document_hash,content_uri,status,
                 effective_at_utc
          from consent.consent_documents
          where id=${documentAction.id}::uuid
          for update
        `;
        if (!previous[0]) {
          throw new ApiError(
            404,
            "legal_document_not_found",
            "Legal document was not found.",
          );
        }
        if (documentAction.action === "publish") {
          if (previous[0].status === "Retired") {
            throw new ApiError(
              409,
              "legal_document_terminal",
              "A retired legal document cannot be republished.",
            );
          }
          if (
            !previous[0].document_hash ||
            !previous[0].content_uri ||
            !previous[0].effective_at_utc
          ) {
            throw new ApiError(
              409,
              "legal_document_incomplete",
              "Legal document requires hash, HTTPS content URI and effective date before publishing.",
            );
          }
          await tx`
            update consent.consent_documents
            set status='Retired'
            where purpose=${String(previous[0].purpose)}
              and jurisdiction=${String(previous[0].jurisdiction)}
              and status='Active'
              and id<>${documentAction.id}::uuid
          `;
        }
        const updated = await tx`
          update consent.consent_documents
          set status=${targetStatus}
          where id=${documentAction.id}::uuid
          returning id,purpose,version,jurisdiction,title,document_hash,content_uri,
                    status,effective_at_utc,created_at_utc
        `;
        const body = { item: updated[0], replayed: false };
        await tx`
          insert into admin.audit_events(
            actor_account_id,action,resource_type,resource_id,result,reason,
            correlation_id,request_id,elevated_access,metadata_json
          ) values (
            ${accountId}::uuid,${operation},'consent_document',${documentAction.id},
            'Succeeded',${payload.reason},${correlationId}::uuid,${idempotencyKey},false,
            jsonb_build_object(
              'previousStatus',${String(previous[0].status)},'status',${targetStatus}
            )
          )
        `;
        await tx`
          update admin.idempotency_keys
          set status='Completed',response_status=200,
              response_json=${JSON.stringify(body)}::jsonb,updated_at_utc=now()
          where actor_account_id=${accountId}::uuid
            and operation=${operation}
            and idempotency_key=${idempotencyKey}
        `;
        return { status: 200, body };
      });
      return json(result.body, result.status, origin);
    }

    const preferencePurpose = matchPreferencePurposePath(path);
    if (request.method === "PATCH" && preferencePurpose) {
      requirePermission(admin, "privacy.governance.write");
      const idempotencyKey = requireIdempotencyKey(request);
      const payload = await parsePreferencePurposeMutation(request);
      const operation = "privacy.preference_purpose.update";
      const hash = await requestHash(operation, {
        purpose: preferencePurpose,
        ...payload,
      });
      const result = await sql.begin(async (tx) => {
        await tx`select pg_advisory_xact_lock(hashtextextended(${accountId + ":" + operation + ":" + idempotencyKey},0))`;
        const existing = await tx`
          select request_hash,status,response_status,response_json
          from admin.idempotency_keys
          where actor_account_id=${accountId}::uuid
            and operation=${operation}
            and idempotency_key=${idempotencyKey}
          limit 1
        `;
        const replay = replayedIdempotentResult(
          existing[0] as StoredIdempotency | undefined,
          hash,
        );
        if (replay) return replay;
        await tx`
          insert into admin.idempotency_keys(
            actor_account_id,operation,idempotency_key,request_hash,status,expires_at_utc
          ) values (
            ${accountId}::uuid,${operation},${idempotencyKey},${hash},'Processing',
            now()+interval '24 hours'
          )
        `;
        const current = await tx`
          select purpose,category,channel,policy_version,default_enabled,
                 user_mutable,status,description
          from consent.preference_purposes
          where purpose=${preferencePurpose}
          for update
        `;
        if (!current[0]) {
          throw new ApiError(
            404,
            "privacy_purpose_not_found",
            "Privacy purpose was not found.",
          );
        }
        const rows = await tx`
          update consent.preference_purposes
          set description=${payload.description},policy_version=${payload.policyVersion},
              status=${payload.status},updated_at_utc=now()
          where purpose=${preferencePurpose}
          returning purpose,category,channel,policy_version,default_enabled,
                    user_mutable,status,description,created_at_utc,updated_at_utc
        `;
        const body = { item: rows[0], replayed: false };
        await tx`
          insert into admin.audit_events(
            actor_account_id,action,resource_type,resource_id,result,reason,
            correlation_id,request_id,elevated_access,metadata_json
          ) values (
            ${accountId}::uuid,${operation},'privacy_preference_purpose',
            ${preferencePurpose},'Succeeded',${payload.reason},${correlationId}::uuid,
            ${idempotencyKey},false,
            jsonb_build_object(
              'previousPolicyVersion',${String(current[0].policy_version)},
              'policyVersion',${payload.policyVersion},
              'previousStatus',${String(current[0].status)},'status',${payload.status}
            )
          )
        `;
        await tx`
          update admin.idempotency_keys
          set status='Completed',response_status=200,
              response_json=${JSON.stringify(body)}::jsonb,updated_at_utc=now()
          where actor_account_id=${accountId}::uuid
            and operation=${operation}
            and idempotency_key=${idempotencyKey}
        `;
        return { status: 200, body };
      });
      return json(result.body, result.status, origin);
    }

    return null;
  };
}

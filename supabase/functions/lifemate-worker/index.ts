import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import postgres from "postgres";
import { createClient } from "supabase";
import { purgeProfilePhotoFolder } from "./account_deletion_storage.ts";
import { createCampaignDeliveryRuntime } from "./campaign_delivery_runtime.ts";
import { publishMarketingContent } from "./marketing_publish_provider.ts";
import {
  boundedMessageTimeoutMs,
  boundedWorkerBatchSize,
  isPermanentWorkerError,
  queueLagLevel,
  retryDelaySeconds,
  supportedEvents,
  workerConsumerName,
} from "./policy.ts";
import { createProviderAuthSubjectResolver } from "./provider_auth_subject.ts";
import { createResearchExportRuntime } from "./research_export_runtime.ts";
import { createResearchExportSignerRoute } from "./research_export_signer_route.ts";
import { loadWorkerDatabaseUrl } from "./runtime_database.ts";
import { schedulerTokenAccepted } from "./scheduler_auth.ts";

const databaseUrl = await loadWorkerDatabaseUrl();
const supabaseUrl = Deno.env.get("SUPABASE_URL");
const serviceRoleKey = Deno.env.get(
  ["SUPABASE", "SERVICE", "ROLE", "KEY"].join("_"),
);
const workerToken = Deno.env.get("LIFEMATE_WORKER_TOKEN");
const researchSignerToken = Deno.env.get("LIFEMATE_RESEARCH_SIGNER_TOKEN");
const workerBatchSize = boundedWorkerBatchSize(
  Deno.env.get("LIFEMATE_WORKER_BATCH_SIZE"),
);
const messageTimeoutMs = boundedMessageTimeoutMs(
  Deno.env.get("LIFEMATE_WORKER_MESSAGE_TIMEOUT_MS"),
);

if (!supabaseUrl || !serviceRoleKey) {
  throw new Error("Required worker runtime configuration is missing.");
}

const sql = postgres(databaseUrl, {
  max: 1,
  idle_timeout: 10,
  connect_timeout: 10,
  prepare: false,
  connection: {
    application_name: "lifemate-worker",
    statement_timeout: messageTimeoutMs,
    lock_timeout: 2000,
    idle_in_transaction_session_timeout: 5000,
  },
});
const providerAuthSubjects = createProviderAuthSubjectResolver(sql);
const admin = createClient(supabaseUrl, serviceRoleKey, {
  auth: { autoRefreshToken: false, persistSession: false },
  global: { fetch: timedFetch },
});
const researchExportRuntime = createResearchExportRuntime(
  sql,
  supabaseUrl,
  serviceRoleKey,
  timedFetch,
);
const researchExportSignerRoute = createResearchExportSignerRoute({
  sql,
  supabaseUrl,
  serviceRoleKey,
  signerToken: researchSignerToken,
  fetcher: timedFetch,
});

let campaignDeliveryRuntime: ReturnType<typeof createCampaignDeliveryRuntime> = null;
let campaignDeliveryConfigurationError: string | null = null;
try {
  campaignDeliveryRuntime = createCampaignDeliveryRuntime(sql, {
    fetcher: timedFetch,
  });
} catch (error) {
  campaignDeliveryConfigurationError = safeErrorCode(error);
  console.warn("Campaign delivery runtime configuration is unavailable", {
    errorCode: campaignDeliveryConfigurationError,
  });
}

type OutboxMessage = {
  id: string;
  aggregate_type: string;
  aggregate_id: string | null;
  event_type: string;
  payload_json: Record<string, unknown>;
  attempt_count: number;
  priority: number;
  max_attempts: number;
  max_age_seconds: number;
  created_at_utc: Date | string;
};

type QueueMetrics = {
  ready_count: number | string;
  processing_count: number | string;
  dead_letter_count: number | string;
  oldest_ready_age_seconds: number | string;
  highest_attempt_count: number | string;
};

type CampaignPublishClaim = {
  execution_id: string;
  campaign_id: string;
  provider_code: string;
  publish_text: string;
  asset_refs: unknown;
  credential_secret_name: string;
};

Deno.serve(async (request: Request) => {
  const researchSignerResponse = await researchExportSignerRoute(request);
  if (researchSignerResponse) return researchSignerResponse;

  if (request.method !== "POST") {
    return response(405, { error: "method_not_allowed" });
  }
  const supplied = request.headers.get("x-lifemate-worker-token") ?? "";
  const operatorAuthenticated = workerToken != null && workerToken.length >= 32
    ? constantTimeEqual(workerToken, supplied)
    : false;
  const schedulerAuthenticated = operatorAuthenticated
    ? false
    : await schedulerTokenAccepted(sql, supplied);
  if (!operatorAuthenticated && !schedulerAuthenticated) {
    return response(401, { error: "unauthorized" });
  }

  const workerId = `edge:${crypto.randomUUID()}`;
  const before = await queueMetrics();
  const claimed = await sql<OutboxMessage[]>`
    with claimed as (
      select *
      from integration.claim_outbox_messages_for_events(
        ${workerId}::character varying,
        ${workerBatchSize},
        ${supportedEvents}::character varying[]
      )
    )
    select c.id,c.aggregate_type,c.aggregate_id,c.event_type,c.payload_json,
           c.attempt_count,m.priority,m.max_attempts,m.max_age_seconds,m.created_at_utc
    from claimed c
    join integration.outbox_messages m on m.id=c.id
    order by m.priority,m.created_at_utc,m.id
  `;

  let processed = 0;
  let failed = 0;
  let replayed = 0;
  let deadLettered = 0;

  for (const message of claimed) {
    try {
      const receipt = await sql`
        select integration.outbox_consumer_receipt_exists(
          ${message.id}::uuid,${workerConsumerName}::character varying
        ) as exists
      `;
      if (receipt[0]?.exists === true) {
        replayed++;
      } else {
        await processMessage(message);
        const recorded = await sql`
          select integration.record_outbox_consumer_receipt(
            ${message.id}::uuid,
            ${workerConsumerName}::character varying,
            ${message.event_type}::character varying
          ) as ok
        `;
        if (recorded[0]?.ok !== true) {
          throw new Error("consumer_receipt_failed");
        }
      }

      const completed = await sql`
        select integration.complete_outbox_message(
          ${message.id}::uuid,${workerId}::character varying
        ) as ok
      `;
      if (completed[0]?.ok !== true) {
        throw new Error("outbox_complete_failed");
      }
      processed++;
    } catch (error) {
      failed++;
      const code = safeErrorCode(error);
      const permanent = isPermanentWorkerError(code);
      const retrySeconds = retryDelaySeconds(
        message.event_type,
        message.attempt_count,
      );
      const ageSeconds = Math.max(
        0,
        Math.floor(
          (Date.now() - new Date(message.created_at_utc).getTime()) / 1000,
        ),
      );
      const expectedDeadLetter = permanent ||
        message.attempt_count >= message.max_attempts ||
        ageSeconds >= message.max_age_seconds;
      const failedRows = await sql`
        select integration.fail_outbox_message_safely(
          ${message.id}::uuid,
          ${workerId}::character varying,
          ${code}::character varying,
          ${retrySeconds},
          ${permanent}
        ) as ok
      `;
      if (failedRows[0]?.ok !== true) {
        console.warn("LifeMate worker could not transition failed item", {
          eventType: message.event_type,
          attempt: message.attempt_count,
          errorCode: code,
        });
      }
      if (expectedDeadLetter) deadLettered++;
      console.warn("LifeMate worker item failed", {
        eventType: message.event_type,
        attempt: message.attempt_count,
        priority: message.priority,
        permanent,
        retrySeconds,
        errorCode: code,
      });
    }
  }

  let campaignDelivery = {
    enabled: campaignDeliveryRuntime !== null,
    claimed: 0,
    delivered: 0,
    failed: 0,
    permanentFailed: 0,
    outcomeUnknown: 0,
    runtimeFailed: campaignDeliveryConfigurationError !== null,
  };
  if (campaignDeliveryRuntime) {
    try {
      const result = await campaignDeliveryRuntime.run(workerBatchSize);
      campaignDelivery = {
        enabled: true,
        ...result,
        runtimeFailed: false,
      };
    } catch (error) {
      const errorCode = safeErrorCode(error);
      console.warn("LifeMate campaign delivery batch failed", { errorCode });
      campaignDelivery = {
        ...campaignDelivery,
        enabled: true,
        runtimeFailed: true,
      };
    }
  }

  const prunedRows = await sql`
    select integration.prune_outbox_history(7,30,250) as deleted
  `;
  const pruned = Number(prunedRows[0]?.deleted ?? 0);
  const after = await queueMetrics();
  const lagLevel = queueLagLevel(after.oldestReadyAgeSeconds);
  if (lagLevel !== "ok") {
    console.warn("LifeMate worker queue lag threshold exceeded", {
      lagLevel,
      readyCount: after.readyCount,
      oldestReadyAgeSeconds: after.oldestReadyAgeSeconds,
      deadLetterCount: after.deadLetterCount,
    });
  }

  return response(200, {
    claimed: claimed.length,
    processed,
    failed,
    replayed,
    deadLettered,
    pruned,
    campaignDelivery,
    queue: {
      before,
      after,
      lagLevel,
    },
  });
});

async function processMessage(message: OutboxMessage): Promise<void> {
  switch (message.event_type) {
    case "care.adherence_projection_refresh_requested": {
      const personId = stringField(message.payload_json, "personId");
      const summaryDate = stringField(message.payload_json, "summaryDate");
      await sql`
        select care.rebuild_daily_adherence_summary(
          ${personId}::uuid,${summaryDate}::date)
      `;
      return;
    }
    case "identity.session_revoke_requested": {
      const accountId = requiredAggregateId(message);
      const authSubject = await providerAuthSubjects.resolve(accountId);
      if (!authSubject) return;
      const { error } = await admin.auth.admin.updateUserById(authSubject, {
        ban_duration: "876000h",
      });
      if (error) {
        throw new Error(`auth_session_revoke:${error.status ?? "error"}`);
      }
      return;
    }
    case "identity.account_deletion_requested": {
      const accountId = requiredAggregateId(message);
      const requestId = stringField(message.payload_json, "requestId");

      const pendingSession = await sql`
        select 1
        from integration.outbox_messages
        where aggregate_id=${accountId}::uuid
          and event_type='identity.session_revoke_requested'
          and status <> 'Processed'
        limit 1
      `;
      if (pendingSession[0]) throw new Error("session_revoke_pending");

      const authSubject = await providerAuthSubjects.resolve(accountId);
      if (authSubject) {
        const { error } = await admin.auth.admin.deleteUser(authSubject, true);
        if (error && error.status !== 404) {
          throw new Error(`auth_delete:${error.status ?? "error"}`);
        }
      }

      // Storage must be removed before SQL finalization clears the profile path.
      // Purging the whole server-owned user folder also removes orphaned previous
      // avatars left by an earlier best-effort replacement cleanup.
      const appUserId = await appUserIdForAccount(accountId);
      if (appUserId) {
        await purgeProfilePhotoFolder(
          admin.storage.from("profile-photos"),
          appUserId,
        );
      }

      const finalized = await sql`
        select identity.finalize_account_deletion(${requestId}::uuid) as ok
      `;
      if (finalized[0]?.ok !== true) {
        throw new Error("deletion_finalize_failed");
      }
      return;
    }
    case "marketing.campaign_publish_requested": {
      const executionId = stringField(message.payload_json, "executionId");
      if (!uuidPattern.test(executionId)) {
        throw new Error("invalid_executionId");
      }

      const rows = await sql<CampaignPublishClaim[]>`
        select * from marketing.claim_campaign_publish_execution(${executionId}::uuid)
      `;
      const claim = rows[0];
      // A missing claim means the execution is already terminal or was failed
      // closed by the database preflight. The outbox item itself can complete.
      if (!claim) return;

      const secretRows = await sql`
        select marketing.resolve_marketing_secret_for_worker(
          ${claim.credential_secret_name}::varchar
        ) as secret
      `;
      const secret = secretRows[0]?.secret;
      if (typeof secret !== "string" || secret.length === 0) {
        const failed = await failCampaignPublish(
          executionId,
          "provider_configuration_missing",
          false,
        );
        if (!failed) throw new Error("publish_fail_transition_failed");
        return;
      }

      const result = await publishMarketingContent(
        {
          providerCode: claim.provider_code,
          publishText: claim.publish_text,
          assetRefs: stringArray(claim.asset_refs),
          credentialSecret: secret,
        },
        timedFetch,
      );

      if (result.kind === "published") {
        const completed = await sql`
          select marketing.complete_campaign_publish_execution(
            ${executionId}::uuid,${result.providerPostRef}::varchar
          ) as ok
        `;
        if (completed[0]?.ok !== true) {
          // The external side effect may already exist. Never retry it blindly.
          await failCampaignPublish(
            executionId,
            "publish_completion_outcome_unknown",
            true,
          );
        }
        return;
      }

      const failed = await failCampaignPublish(
        executionId,
        result.code,
        result.kind === "unknown",
      );
      if (!failed) throw new Error("publish_fail_transition_failed");
      return;
    }
    case "analytics.research_export_requested": {
      const jobId = stringField(message.payload_json, "jobId");
      if (!uuidPattern.test(jobId)) {
        throw new Error("invalid_jobId");
      }
      await researchExportRuntime.process(jobId);
      return;
    }
    default:
      throw new Error("unsupported_event");
  }
}

async function failCampaignPublish(
  executionId: string,
  code: string,
  outcomeUnknown: boolean,
): Promise<boolean> {
  const rows = await sql`
    select marketing.fail_campaign_publish_execution(
      ${executionId}::uuid,${code}::varchar,${outcomeUnknown}
    ) as ok
  `;
  return rows[0]?.ok === true;
}

async function queueMetrics(): Promise<{
  readyCount: number;
  processingCount: number;
  deadLetterCount: number;
  oldestReadyAgeSeconds: number;
  highestAttemptCount: number;
}> {
  const rows = await sql<QueueMetrics[]>`
    select * from integration.outbox_queue_metrics(
      ${supportedEvents}::character varying[]
    )
  `;
  const row = rows[0];
  return {
    readyCount: Number(row?.ready_count ?? 0),
    processingCount: Number(row?.processing_count ?? 0),
    deadLetterCount: Number(row?.dead_letter_count ?? 0),
    oldestReadyAgeSeconds: Number(row?.oldest_ready_age_seconds ?? 0),
    highestAttemptCount: Number(row?.highest_attempt_count ?? 0),
  };
}

async function timedFetch(
  input: RequestInfo | URL,
  init?: RequestInit,
): Promise<Response> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), messageTimeoutMs);
  try {
    return await fetch(input, { ...init, signal: controller.signal });
  } finally {
    clearTimeout(timeout);
  }
}

async function appUserIdForAccount(accountId: string): Promise<string | null> {
  const rows = await sql`
    select coalesce(a.legacy_app_user_id, legacy.id) as app_user_id
    from identity.accounts a
    left join lifemate.app_users legacy on legacy.id = a.id
    where a.id=${accountId}::uuid
    limit 1
  `;
  const value = rows[0]?.app_user_id;
  return typeof value === "string" && uuidPattern.test(value) ? value : null;
}

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function requiredAggregateId(message: OutboxMessage): string {
  if (!message.aggregate_id) throw new Error("aggregate_id_missing");
  return message.aggregate_id;
}

function stringField(value: Record<string, unknown>, field: string): string {
  const result = value?.[field];
  if (
    typeof result !== "string" || result.length === 0 || result.length > 256
  ) {
    throw new Error(`invalid_${field}`);
  }
  return result;
}

function stringArray(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value.filter((item): item is string => typeof item === "string");
}

function safeErrorCode(error: unknown): string {
  const raw = error instanceof Error ? error.message : "worker_error";
  if (error instanceof DOMException && error.name === "AbortError") {
    return "downstream_timeout";
  }
  return raw.replace(/[^a-zA-Z0-9:_-]/g, "_").slice(0, 80) || "worker_error";
}

function constantTimeEqual(expected: string, actual: string): boolean {
  const encoder = new TextEncoder();
  const a = encoder.encode(expected);
  const b = encoder.encode(actual);
  let difference = a.length ^ b.length;
  const length = Math.max(a.length, b.length);
  for (let i = 0; i < length; i++) {
    difference |= (a[i % a.length] ?? 0) ^
      (b[i % Math.max(1, b.length)] ?? 0);
  }
  return difference === 0;
}

function response(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store",
    },
  });
}

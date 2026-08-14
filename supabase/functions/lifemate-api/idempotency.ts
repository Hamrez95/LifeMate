import { getLifeMateSql } from "./database_client.ts";
import { corsHeaders } from "./http.ts";
import { ApiError } from "./validation.ts";

type Row = Record<string, unknown>;

const mutationMethods = new Set(["POST", "PATCH", "DELETE"]);
const maximumStoredResponseBytes = 64 * 1024;

export function shouldProtectMutation(method: string, path: string): boolean {
  if (!path.startsWith("/api/v1/")) return false;
  if (mutationMethods.has(method)) return true;
  // Daily logs are JSON upserts. Binary profile-photo PUT deliberately remains
  // outside this generic coordinator because its body is not JSON and storage
  // compensation has a separate contract.
  return method === "PUT" && path === "/api/v1/women-calendar/daily-logs";
}

export function requireMutationIdempotencyKey(request: Request): string {
  const value = request.headers.get("idempotency-key")?.trim() ?? "";
  if (!/^[A-Za-z0-9._:-]{8,180}$/.test(value)) {
    throw new ApiError(
      400,
      "idempotency_key_required",
      "A valid Idempotency-Key header is required for this mutation.",
    );
  }
  return value;
}

export async function requestHash(body: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(body),
  );
  return [...new Uint8Array(digest)]
    .map((value) => value.toString(16).padStart(2, "0"))
    .join("");
}

export function createMutationIdempotencyStore(databaseUrl: string) {
  const sql = getLifeMateSql(databaseUrl);

  async function execute(
    actorAuthSubject: string,
    operation: string,
    idempotencyKey: string,
    requestBody: string,
    action: () => Promise<Response>,
  ): Promise<Response> {
    const hash = await requestHash(requestBody);

    // Reclaim expired rows in small sampled batches so retention stays bounded
    // without adding a cleanup query to every healthcare mutation. Exact-key
    // expiry is handled atomically by the claim below.
    if (Number.parseInt(hash.slice(0, 2), 16) < 4) {
      await sql`
        delete from lifemate.idempotency_keys
        where ctid in (
          select ctid
          from lifemate.idempotency_keys
          where expires_at_utc <= now()
          order by expires_at_utc
          limit 100
        )
      `;
    }

    const claimed = await sql`
      insert into lifemate.idempotency_keys
        (actor_auth_subject, operation, idempotency_key, request_hash,
         status, response_status, response_body, created_at_utc,
         updated_at_utc, expires_at_utc)
      values
        (${actorAuthSubject}::uuid, ${operation}, ${idempotencyKey}, ${hash},
         'Processing', null, null, now(), now(), now() + interval '24 hours')
      on conflict (actor_auth_subject, operation, idempotency_key)
      do update set
        request_hash = excluded.request_hash,
        status = 'Processing',
        response_status = null,
        response_body = null,
        created_at_utc = excluded.created_at_utc,
        updated_at_utc = excluded.updated_at_utc,
        expires_at_utc = excluded.expires_at_utc
      where lifemate.idempotency_keys.expires_at_utc <= now()
      returning actor_auth_subject
    `;

    if (!claimed[0]) {
      const existingRows = await sql`
        select request_hash, status, response_status, response_body,
               expires_at_utc
        from lifemate.idempotency_keys
        where actor_auth_subject = ${actorAuthSubject}::uuid
          and operation = ${operation}
          and idempotency_key = ${idempotencyKey}
        limit 1
      `;
      const existing = existingRows[0] as Row | undefined;
      if (!existing) {
        throw new ApiError(
          503,
          "idempotency_state_unavailable",
          "Mutation retry state is temporarily unavailable.",
        );
      }
      if (String(existing.request_hash) !== hash) {
        throw new ApiError(
          409,
          "idempotency_key_reused",
          "Idempotency-Key was already used with a different request payload.",
        );
      }
      if (String(existing.status) !== "Completed") {
        throw new ApiError(
          409,
          "idempotency_in_progress",
          "A matching mutation is already being processed. Retry shortly.",
        );
      }
      const responseStatus = Number(existing.response_status);
      if (
        !Number.isInteger(responseStatus) || responseStatus < 200 ||
        responseStatus > 299
      ) {
        throw new ApiError(
          503,
          "idempotency_state_unavailable",
          "Stored mutation response is unavailable.",
        );
      }
      return new Response(
        existing.response_body == null ? null : String(existing.response_body),
        {
          status: responseStatus,
          headers: {
            ...corsHeaders,
            "X-Idempotency-Replayed": "true",
          },
        },
      );
    }

    let response: Response;
    try {
      response = await action();
    } catch (error) {
      // Route/store failures are transactional in the current healthcare API.
      // Releasing the claim allows a caller to retry a request that did not
      // produce a successful response. If the Edge isolate itself disappears
      // after a domain commit, the Processing row remains and fails closed
      // rather than blindly duplicating a critical write.
      await sql`
        delete from lifemate.idempotency_keys
        where actor_auth_subject = ${actorAuthSubject}::uuid
          and operation = ${operation}
          and idempotency_key = ${idempotencyKey}
          and status = 'Processing'
      `.catch(() => undefined);
      throw error;
    }

    const storedBody = await response.clone().text();
    if (
      new TextEncoder().encode(storedBody).byteLength >
        maximumStoredResponseBytes
    ) {
      await sql`
        delete from lifemate.idempotency_keys
        where actor_auth_subject = ${actorAuthSubject}::uuid
          and operation = ${operation}
          and idempotency_key = ${idempotencyKey}
          and status = 'Processing'
      `.catch(() => undefined);
      throw new ApiError(
        500,
        "idempotency_response_too_large",
        "Mutation response exceeded the replay safety limit.",
      );
    }

    // Do not convert this completion failure into a reusable key. A successful
    // domain mutation followed by a ledger write failure is uncertain; leaving
    // Processing in place makes subsequent retries fail closed instead of
    // producing a duplicate side effect.
    const completed = await sql`
      update lifemate.idempotency_keys
      set status = 'Completed', response_status = ${response.status},
          response_body = ${storedBody.length === 0 ? null : storedBody},
          updated_at_utc = now()
      where actor_auth_subject = ${actorAuthSubject}::uuid
        and operation = ${operation}
        and idempotency_key = ${idempotencyKey}
        and request_hash = ${hash}
        and status = 'Processing'
      returning idempotency_key
    `;
    if (!completed[0]) {
      throw new ApiError(
        503,
        "idempotency_state_unavailable",
        "Mutation completed but replay state could not be persisted.",
      );
    }
    return response;
  }

  return { execute };
}

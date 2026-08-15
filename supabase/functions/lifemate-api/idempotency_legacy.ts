import type { LifeMateSql } from "./database_client.ts";

export type LegacyIdempotencyReplayRow = {
  request_hash: string;
  status: string;
  response_status: number | null;
  response_body: string | null;
};

/**
 * Temporary <=24h migration bridge for idempotency rows written before actor
 * tokenization. This module is the only non-identity runtime compatibility
 * module permitted to query the old raw Auth-subject ledger key.
 *
 * New rows are never written here. Once production has run the tokenized
 * idempotency path for longer than the maximum ledger TTL and token-only
 * identity activation is proven, this module and the raw column can be removed.
 */
export async function findLegacyIdempotencyReplay(
  sql: LifeMateSql,
  actorAuthSubject: string,
  operation: string,
  idempotencyKey: string,
): Promise<LegacyIdempotencyReplayRow | null> {
  const rows = await sql<LegacyIdempotencyReplayRow[]>`
    select request_hash, status, response_status, response_body
    from lifemate.idempotency_keys
    where actor_auth_subject=${actorAuthSubject}::uuid
      and operation=${operation}
      and idempotency_key=${idempotencyKey}
      and expires_at_utc > now()
    limit 1
  `;
  return rows[0] ?? null;
}

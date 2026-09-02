import type { ProductTelemetry } from "./privacy_safe_event.ts";

export type ProductActivityPersistenceResult = "inserted" | "duplicate";

type FetchLike = (
  input: RequestInfo | URL,
  init?: RequestInit,
) => Promise<Response>;

export function productActivityRpcPayload(
  event: ProductTelemetry,
): Record<string, unknown> {
  return {
    p_event_id: event.eventId,
    p_product: event.application,
    p_event_name: event.eventName,
    p_definition_version: 1,
    p_release_version: event.releaseVersion,
    p_platform: event.platform,
    p_locale_family: event.localeFamily,
    p_connectivity: event.connectivity,
    p_outcome: event.outcome,
  };
}

export async function persistProductActivity(
  event: ProductTelemetry,
  options: {
    supabaseUrl: string;
    publishableKey: string;
    authorization: string;
    fetcher?: FetchLike;
  },
): Promise<ProductActivityPersistenceResult> {
  const fetcher = options.fetcher ?? fetch;
  const response = await fetcher(
    `${options.supabaseUrl}/rest/v1/rpc/record_product_activity_event`,
    {
      method: "POST",
      headers: {
        Accept: "application/json",
        Authorization: options.authorization,
        apikey: options.publishableKey,
        "Content-Type": "application/json",
        "X-Client-Info": "lifemate-telemetry/1",
      },
      body: JSON.stringify(productActivityRpcPayload(event)),
      signal: AbortSignal.timeout(5_000),
    },
  );

  if (!response.ok) {
    // Never forward the PostgREST body because database/provider diagnostics may
    // contain implementation details. The caller logs only this bounded code.
    throw new Error("product_activity_persistence_failed");
  }

  let body: unknown;
  try {
    body = await response.json();
  } catch (_) {
    throw new Error("product_activity_persistence_failed");
  }
  if (body !== "inserted" && body !== "duplicate") {
    throw new Error("product_activity_persistence_failed");
  }
  return body;
}

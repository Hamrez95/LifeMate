import { assertEquals, assertRejects } from "jsr:@std/assert@1.0.14";
import { parseProductTelemetry } from "./privacy_safe_event.ts";
import {
  persistProductActivity,
  productActivityRpcPayload,
} from "./product_activity_persistence.ts";

const canonical = parseProductTelemetry({
  kind: "product",
  eventId: "123e4567-e89b-42d3-a456-426614174888",
  application: "wellmate",
  releaseVersion: "0.9.0-internal.9+20",
  platform: "android",
  eventName: "app_opened",
  localeFamily: "fa",
  connectivity: "online",
  outcome: "success",
});

Deno.test("legacy app_open normalizes to canonical app_opened", () => {
  const legacy = parseProductTelemetry({
    kind: "product",
    eventId: "123e4567-e89b-42d3-a456-426614174889",
    application: "caremate",
    releaseVersion: "0.9.0",
    platform: "android",
    eventName: "app_open",
    localeFamily: "en",
    connectivity: "unknown",
    outcome: "success",
  });
  assertEquals(legacy.eventName, "app_opened");
});

Deno.test("RPC payload is bounded and contains no account or arbitrary metadata", () => {
  const payload = productActivityRpcPayload(canonical);
  assertEquals(payload, {
    p_event_id: canonical.eventId,
    p_product: "wellmate",
    p_event_name: "app_opened",
    p_definition_version: 1,
    p_release_version: canonical.releaseVersion,
    p_platform: "android",
    p_locale_family: "fa",
    p_connectivity: "online",
    p_outcome: "success",
  });
  for (const forbidden of [
    "account",
    "user",
    "person",
    "medication",
    "symptom",
    "diagnosis",
    "cycle",
    "pregnancy",
    "note",
    "metadata",
  ]) {
    assertEquals(JSON.stringify(payload).toLowerCase().includes(forbidden), false);
  }
});

Deno.test("persistence uses the caller bearer token and accepts inserted/duplicate", async () => {
  for (const status of ["inserted", "duplicate"] as const) {
    let observed: { url: string; init?: RequestInit } | undefined;
    const result = await persistProductActivity(canonical, {
      supabaseUrl: "https://example.supabase.co",
      publishableKey: "sb_publishable_test_key_0123456789",
      authorization: "Bearer user-access-token",
      fetcher: async (input, init) => {
        observed = { url: String(input), init };
        return new Response(JSON.stringify(status), {
          status: 200,
          headers: { "Content-Type": "application/json" },
        });
      },
    });
    assertEquals(result, status);
    assertEquals(
      observed?.url,
      "https://example.supabase.co/rest/v1/rpc/record_product_activity_event",
    );
    const headers = new Headers(observed?.init?.headers);
    assertEquals(headers.get("Authorization"), "Bearer user-access-token");
    const body = JSON.parse(String(observed?.init?.body));
    assertEquals(body.p_event_name, "app_opened");
    assertEquals("p_account_id" in body, false);
    assertEquals("metadata" in body, false);
  }
});

Deno.test("persistence failure exposes only a bounded safe error", async () => {
  await assertRejects(
    () =>
      persistProductActivity(canonical, {
        supabaseUrl: "https://example.supabase.co",
        publishableKey: "sb_publishable_test_key_0123456789",
        authorization: "Bearer user-access-token",
        fetcher: async () =>
          new Response("private database implementation detail", { status: 500 }),
      }),
    Error,
    "product_activity_persistence_failed",
  );
});

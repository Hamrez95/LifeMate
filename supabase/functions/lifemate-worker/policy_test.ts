import {
  assertEquals,
  assertNotEquals,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  boundedMessageTimeoutMs,
  boundedWorkerBatchSize,
  isPermanentWorkerError,
  queueLagLevel,
  retryDelaySeconds,
} from "./policy.ts";

Deno.test("worker batch and message timeouts are bounded", () => {
  assertEquals(boundedWorkerBatchSize(undefined), 20);
  assertEquals(boundedWorkerBatchSize("1"), 1);
  assertEquals(boundedWorkerBatchSize("50"), 50);
  assertEquals(boundedWorkerBatchSize("500"), 20);
  assertEquals(boundedWorkerBatchSize("nope"), 20);

  assertEquals(boundedMessageTimeoutMs(undefined), 8000);
  assertEquals(boundedMessageTimeoutMs("1000"), 1000);
  assertEquals(boundedMessageTimeoutMs("20000"), 20000);
  assertEquals(boundedMessageTimeoutMs("50000"), 8000);
});

Deno.test("retry delay is exponential, jittered and capped", () => {
  const first = retryDelaySeconds("identity.session_revoke_requested", 1, 0.5);
  const second = retryDelaySeconds("identity.session_revoke_requested", 2, 0.5);
  const capped = retryDelaySeconds("identity.session_revoke_requested", 20, 1);
  assertEquals(first, 30);
  assertEquals(second, 60);
  assertEquals(capped, 3600);

  const lowJitter = retryDelaySeconds(
    "care.adherence_projection_refresh_requested",
    3,
    0,
  );
  const highJitter = retryDelaySeconds(
    "care.adherence_projection_refresh_requested",
    3,
    1,
  );
  assertNotEquals(lowJitter, highJitter);
});

Deno.test("poison errors are dead-lettered immediately", () => {
  assertEquals(isPermanentWorkerError("unsupported_event"), true);
  assertEquals(isPermanentWorkerError("aggregate_id_missing"), true);
  assertEquals(isPermanentWorkerError("invalid_personId"), true);
  assertEquals(isPermanentWorkerError("provider_handle_missing"), true);
  assertEquals(isPermanentWorkerError("provider_handle_decrypt_failed"), true);
  assertEquals(isPermanentWorkerError("auth_delete:400"), true);
  assertEquals(isPermanentWorkerError("auth_delete:429"), false);
  assertEquals(isPermanentWorkerError("auth_session_revoke:503"), false);
  assertEquals(isPermanentWorkerError("session_revoke_pending"), false);
});

Deno.test("queue lag has explicit operational thresholds", () => {
  assertEquals(queueLagLevel(0), "ok");
  assertEquals(queueLagLevel(119), "ok");
  assertEquals(queueLagLevel(120), "warn");
  assertEquals(queueLagLevel(899), "warn");
  assertEquals(queueLagLevel(900), "critical");
});

import { assert, assertEquals, assertRejects } from "jsr:@std/assert@1.0.14";
import {
  cloudProviderPolicySummary,
  evaluateGatewayRequest,
  type GatewayPolicy,
  validateGatewayPolicy,
} from "./gateway_policy.ts";

const policyUrl = new URL(
  "../../config/lifemate-edge-gateway-policy.json",
  import.meta.url,
);

async function loadPolicy(): Promise<GatewayPolicy> {
  return JSON.parse(await Deno.readTextFile(policyUrl)) as GatewayPolicy;
}

Deno.test("canonical gateway policy validates and begins in log mode", async () => {
  const policy = await loadPolicy();
  validateGatewayPolicy(policy);
  assertEquals(policy.rollout.initialMode, "log");
  assertEquals(policy.rollout.stages, ["log", "simulate", "block"]);
  for (const value of Object.values(policy.classes)) {
    assertEquals(value.outerRateLimit.counterScope, "source_ip");
  }
});

Deno.test("log and simulate stages observe without rejecting traffic", async () => {
  const policy = await loadPolicy();
  for (const mode of ["log", "simulate"] as const) {
    const decision = evaluateGatewayRequest(
      policy,
      {
        method: "POST",
        path: "/api/v1/treatment-plans",
        contentLength: 64 * 1024,
        contentType: "application/json",
      },
      mode,
    );
    assertEquals(decision.action, "allow");
    assertEquals(decision.observedOnly, true);
  }
});

Deno.test("block mode enforces application-aligned JSON and media bounds", async () => {
  const policy = await loadPolicy();
  const oversizedJson = evaluateGatewayRequest(
    policy,
    {
      method: "POST",
      path: "/api/v1/treatment-plans",
      contentLength: 32 * 1024 + 1,
      contentType: "application/json",
    },
    "block",
  );
  assertEquals(oversizedJson.action, "reject");
  if (oversizedJson.action === "reject") {
    assertEquals(oversizedJson.status, 413);
  }

  const validPhoto = evaluateGatewayRequest(
    policy,
    {
      method: "PUT",
      path: "/api/v1/me/profile/photo",
      contentLength: 3 * 1024 * 1024,
      contentType: "image/webp",
    },
    "block",
  );
  assertEquals(validPhoto.action, "allow");

  const oversizedPhoto = evaluateGatewayRequest(
    policy,
    {
      method: "PUT",
      path: "/api/v1/me/profile/photo",
      contentLength: 3 * 1024 * 1024 + 1,
      contentType: "image/webp",
    },
    "block",
  );
  assertEquals(oversizedPhoto.action, "reject");
  if (oversizedPhoto.action === "reject") {
    assertEquals(oversizedPhoto.status, 413);
  }

  const wrongPhotoType = evaluateGatewayRequest(
    policy,
    {
      method: "PUT",
      path: "/api/v1/me/profile/photo",
      contentLength: 1024,
      contentType: "application/octet-stream",
    },
    "block",
  );
  assertEquals(wrongPhotoType.action, "reject");
  if (wrongPhotoType.action === "reject") {
    assertEquals(wrongPhotoType.status, 415);
  }
});

Deno.test("GET account export receives the sensitive outer class", async () => {
  const policy = await loadPolicy();
  const decision = evaluateGatewayRequest(
    policy,
    {
      method: "GET",
      path: "/api/v1/account/data-export",
      contentLength: 0,
    },
    "block",
  );
  assertEquals(decision.action, "allow");
  assertEquals(decision.routeId, "sensitive-account-data-export");
  assertEquals(decision.className, "sensitive-write");
});

Deno.test("protect-core mode preserves critical medication reports", async () => {
  const policy = await loadPolicy();
  const decision = evaluateGatewayRequest(
    policy,
    {
      method: "POST",
      path:
        "/api/v1/dose-occurrences/123e4567-e89b-42d3-a456-426614174888/report",
      contentLength: 512,
      contentType: "application/json; charset=utf-8",
    },
    "protect_core",
  );

  assertEquals(decision.action, "allow");
  assertEquals(decision.routeId, "critical-dose-report");
  assertEquals(decision.className, "critical-healthcare-write");
  assertEquals(decision.observedOnly, false);
});

Deno.test("protect-core mode sheds expensive and ordinary work with 429", async () => {
  const policy = await loadPolicy();
  for (
    const path of [
      "/api/v1/home-snapshot",
      "/api/v1/care/relationships",
    ]
  ) {
    const decision = evaluateGatewayRequest(
      policy,
      { method: "GET", path, contentLength: 0 },
      "protect_core",
    );
    assertEquals(decision.action, "reject");
    if (decision.action === "reject") {
      assertEquals(decision.status, 429);
      assertEquals(decision.retryAfterSeconds, 30);
    }
  }
});

Deno.test("unsafe HTTP methods are rejected only after staged enforcement", async () => {
  const policy = await loadPolicy();
  const observed = evaluateGatewayRequest(
    policy,
    { method: "TRACE", path: "/api/v1/me", contentLength: 0 },
    "log",
  );
  assertEquals(observed.action, "allow");
  assertEquals(observed.observedOnly, true);

  const blocked = evaluateGatewayRequest(
    policy,
    { method: "TRACE", path: "/api/v1/me", contentLength: 0 },
    "block",
  );
  assertEquals(blocked.action, "reject");
  if (blocked.action === "reject") {
    assertEquals(blocked.status, 405);
  }
});

Deno.test("generic API fallback never shadows critical route", async () => {
  const policy = await loadPolicy();
  const critical = evaluateGatewayRequest(
    policy,
    {
      method: "POST",
      path:
        "/api/v1/dose-occurrences/123e4567-e89b-42d3-a456-426614174888/report",
      contentLength: 128,
      contentType: "application/json",
    },
    "block",
  );
  assertEquals(critical.routeId, "critical-dose-report");

  const generic = evaluateGatewayRequest(
    policy,
    {
      method: "POST",
      path: "/api/v1/treatment-plans",
      contentLength: 128,
      contentType: "application/json",
    },
    "block",
  );
  assertEquals(generic.routeId, "api-writes");
});

Deno.test("provider handoff summary contains policy only, not runtime secrets", async () => {
  const policy = await loadPolicy();
  const serialized = JSON.stringify(cloudProviderPolicySummary(policy));
  for (
    const forbidden of [
      "Authorization",
      "Bearer ",
      "SUPABASE_SERVICE_ROLE_KEY",
      "UPSTASH_REDIS_REST_TOKEN",
      "postgresql://",
    ]
  ) {
    assert(!serialized.includes(forbidden));
  }
  assert(serialized.includes("source_ip"));
});

Deno.test("policy validator rejects ambiguous gateway counter scope", async () => {
  const policy = await loadPolicy();
  const unsafe = structuredClone(policy);
  unsafe.classes.read.outerRateLimit.counterScope = "global" as "source_ip";
  await assertRejects(
    async () => validateGatewayPolicy(unsafe),
    Error,
    "invalid_gateway_counter_scope",
  );
});

Deno.test("policy validator fails if critical healthcare is shed in emergency", async () => {
  const policy = await loadPolicy();
  const unsafe = structuredClone(policy);
  unsafe.classes["critical-healthcare-write"].emergencyAction = "rate_limit";
  await assertRejects(
    async () => validateGatewayPolicy(unsafe),
    Error,
    "critical_healthcare_must_survive_emergency_mode",
  );
});

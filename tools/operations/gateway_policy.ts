export type GatewayMode = "log" | "simulate" | "block" | "protect_core";
export type GatewayEmergencyAction = "allow" | "rate_limit";
export type GatewayCounterScope = "source_ip";

export type GatewayPolicy = {
  schemaVersion: 1;
  rollout: {
    initialMode: "log";
    stages: Array<"log" | "simulate" | "block">;
    minimumObservationMinutes: number;
  };
  responses: {
    rateLimitedStatus: 429;
    retryAfterSeconds: number;
    tooLargeStatus: 413;
    unsupportedMediaStatus: 415;
    methodNotAllowedStatus: 405;
  };
  defaults: {
    jsonMaximumBytes: number;
    binaryMaximumBytes: number;
    allowedMethods: string[];
  };
  classes: Record<
    string,
    {
      outerRateLimit: {
        requests: number;
        windowSeconds: number;
        counterScope: GatewayCounterScope;
      };
      emergencyAction: GatewayEmergencyAction;
    }
  >;
  routes: Array<{
    id: string;
    class: string;
    methods: string[];
    pathPattern: string;
    maximumBodyBytes: number;
    contentTypes: string[];
  }>;
};

export type GatewayRequest = {
  method: string;
  path: string;
  contentLength: number;
  contentType?: string | null;
};

export type GatewayDecision =
  | {
    action: "allow";
    routeId: string | null;
    className: string | null;
    observedOnly: boolean;
  }
  | {
    action: "reject";
    routeId: string | null;
    className: string | null;
    status: 405 | 413 | 415 | 429;
    retryAfterSeconds?: number;
    observedOnly: boolean;
  };

const uuidRouteFragment = "[0-9a-fA-F-]{36}";

export function validateGatewayPolicy(policy: GatewayPolicy): void {
  if (policy.schemaVersion !== 1) throw new Error("unsupported_schema_version");
  if (policy.rollout.initialMode !== "log") {
    throw new Error("gateway_must_start_in_log_mode");
  }
  if (policy.rollout.stages.join(",") !== "log,simulate,block") {
    throw new Error("invalid_gateway_rollout_order");
  }
  integerBetween(
    policy.rollout.minimumObservationMinutes,
    15,
    24 * 60,
    "minimum_observation_minutes",
  );
  if (policy.responses.rateLimitedStatus !== 429) {
    throw new Error("gateway_rate_limit_must_be_429");
  }
  integerBetween(
    policy.responses.retryAfterSeconds,
    1,
    300,
    "retry_after_seconds",
  );
  if (policy.responses.tooLargeStatus !== 413) {
    throw new Error("invalid_413_contract");
  }
  if (policy.responses.unsupportedMediaStatus !== 415) {
    throw new Error("invalid_415_contract");
  }
  if (policy.responses.methodNotAllowedStatus !== 405) {
    throw new Error("invalid_405_contract");
  }
  if (policy.defaults.jsonMaximumBytes !== 32 * 1024) {
    throw new Error("json_body_limit_must_match_application");
  }
  if (policy.defaults.binaryMaximumBytes !== 3 * 1024 * 1024) {
    throw new Error("binary_body_limit_must_match_application");
  }

  const allowedMethods = new Set(
    policy.defaults.allowedMethods.map((method) => method.toUpperCase()),
  );
  if (allowedMethods.has("TRACE") || allowedMethods.has("CONNECT")) {
    throw new Error("unsafe_gateway_method_enabled");
  }
  for (
    const required of ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"]
  ) {
    if (!allowedMethods.has(required)) {
      throw new Error(`missing_method_${required}`);
    }
  }

  const routeIds = new Set<string>();
  let criticalRouteFound = false;
  let genericReadIndex = -1;
  let genericWriteIndex = -1;
  for (const [index, route] of policy.routes.entries()) {
    if (!/^[a-z][a-z0-9-]{2,63}$/.test(route.id)) {
      throw new Error("invalid_gateway_route_id");
    }
    if (routeIds.has(route.id)) throw new Error("duplicate_gateway_route_id");
    routeIds.add(route.id);
    if (!policy.classes[route.class]) throw new Error("unknown_gateway_class");
    if (
      !route.pathPattern.startsWith("^") || !route.pathPattern.endsWith("$")
    ) {
      throw new Error("gateway_patterns_must_be_anchored");
    }
    new RegExp(route.pathPattern);
    if (
      route.maximumBodyBytes < 0 ||
      route.maximumBodyBytes > policy.defaults.binaryMaximumBytes
    ) {
      throw new Error("invalid_route_body_limit");
    }
    for (const method of route.methods) {
      if (!allowedMethods.has(method.toUpperCase())) {
        throw new Error("route_uses_disallowed_method");
      }
    }
    for (const type of route.contentTypes) {
      if (!/^[a-z0-9.+-]+\/[a-z0-9.+-]+$/i.test(type)) {
        throw new Error("invalid_gateway_content_type");
      }
    }
    if (route.id === "critical-dose-report") {
      criticalRouteFound = route.class === "critical-healthcare-write" &&
        policy.classes[route.class].emergencyAction === "allow" &&
        route.methods.length === 1 && route.methods[0] === "POST" &&
        route.pathPattern.includes(uuidRouteFragment) &&
        route.maximumBodyBytes === policy.defaults.jsonMaximumBytes;
    }
    if (route.id === "api-reads") genericReadIndex = index;
    if (route.id === "api-writes") genericWriteIndex = index;
  }
  if (!criticalRouteFound) {
    throw new Error("critical_healthcare_route_not_protected");
  }
  const criticalIndex = policy.routes.findIndex((route) =>
    route.id === "critical-dose-report"
  );
  if (
    criticalIndex < 0 || genericWriteIndex < 0 ||
    criticalIndex > genericWriteIndex
  ) {
    throw new Error("critical_route_must_precede_generic_write");
  }
  if (genericReadIndex < 0 || genericWriteIndex < 0) {
    throw new Error("generic_api_fallback_routes_required");
  }

  for (const [className, value] of Object.entries(policy.classes)) {
    if (!/^[a-z][a-z0-9-]{2,63}$/.test(className)) {
      throw new Error("invalid_gateway_class");
    }
    integerBetween(
      value.outerRateLimit.requests,
      1,
      100_000,
      "outer_rate_requests",
    );
    integerBetween(
      value.outerRateLimit.windowSeconds,
      1,
      3600,
      "outer_rate_window",
    );
    if (value.outerRateLimit.counterScope !== "source_ip") {
      throw new Error("invalid_gateway_counter_scope");
    }
    if (
      className === "critical-healthcare-write" &&
      value.emergencyAction !== "allow"
    ) {
      throw new Error("critical_healthcare_must_survive_emergency_mode");
    }
  }
}

export function evaluateGatewayRequest(
  policy: GatewayPolicy,
  request: GatewayRequest,
  mode: GatewayMode,
): GatewayDecision {
  validateGatewayPolicy(policy);
  const observedOnly = mode === "log" || mode === "simulate";
  const method = request.method.trim().toUpperCase();
  const path = normalizePath(request.path);
  const allowedMethods = new Set(policy.defaults.allowedMethods);

  if (!allowedMethods.has(method)) {
    return rejectOrObserve(
      observedOnly,
      null,
      null,
      policy.responses.methodNotAllowedStatus,
    );
  }
  if (method === "OPTIONS") {
    return { action: "allow", routeId: null, className: null, observedOnly };
  }

  const route = policy.routes.find((candidate) =>
    candidate.methods.includes(method) &&
    new RegExp(candidate.pathPattern).test(path)
  );
  if (!route) {
    return { action: "allow", routeId: null, className: null, observedOnly };
  }

  if (
    !Number.isFinite(request.contentLength) || request.contentLength < 0 ||
    request.contentLength > route.maximumBodyBytes
  ) {
    return rejectOrObserve(
      observedOnly,
      route.id,
      route.class,
      policy.responses.tooLargeStatus,
    );
  }
  if (request.contentLength > 0 && route.contentTypes.length > 0) {
    const contentType = (request.contentType ?? "").split(";", 1)[0].trim()
      .toLowerCase();
    if (!route.contentTypes.includes(contentType)) {
      return rejectOrObserve(
        observedOnly,
        route.id,
        route.class,
        policy.responses.unsupportedMediaStatus,
      );
    }
  }

  const gatewayClass = policy.classes[route.class];
  if (
    mode === "protect_core" && gatewayClass.emergencyAction === "rate_limit"
  ) {
    return rejectOrObserve(
      false,
      route.id,
      route.class,
      policy.responses.rateLimitedStatus,
      policy.responses.retryAfterSeconds,
    );
  }

  return {
    action: "allow",
    routeId: route.id,
    className: route.class,
    observedOnly,
  };
}

export function cloudProviderPolicySummary(
  policy: GatewayPolicy,
): Record<string, unknown> {
  validateGatewayPolicy(policy);
  return {
    schemaVersion: policy.schemaVersion,
    rollout: policy.rollout,
    responseContract: policy.responses,
    routeClasses: Object.entries(policy.classes).map(([name, value]) => ({
      name,
      rate: value.outerRateLimit,
      emergencyAction: value.emergencyAction,
    })),
    routes: policy.routes.map((route) => ({
      id: route.id,
      class: route.class,
      methods: route.methods,
      pathPattern: route.pathPattern,
      maximumBodyBytes: route.maximumBodyBytes,
      contentTypes: route.contentTypes,
    })),
  };
}

function rejectOrObserve(
  observedOnly: boolean,
  routeId: string | null,
  className: string | null,
  status: 405 | 413 | 415 | 429,
  retryAfterSeconds?: number,
): GatewayDecision {
  if (observedOnly) {
    return { action: "allow", routeId, className, observedOnly: true };
  }
  return {
    action: "reject",
    routeId,
    className,
    status,
    ...(retryAfterSeconds == null ? {} : { retryAfterSeconds }),
    observedOnly: false,
  };
}

function normalizePath(value: string): string {
  const path = value.split("?", 1)[0] || "/";
  if (!path.startsWith("/")) return `/${path}`;
  return path.length > 1 && path.endsWith("/") ? path.slice(0, -1) : path;
}

function integerBetween(
  value: number,
  min: number,
  max: number,
  field: string,
): void {
  if (!Number.isInteger(value) || value < min || value > max) {
    throw new Error(`invalid_${field}`);
  }
}

if (import.meta.main) {
  const source = Deno.args[0];
  const output = Deno.args[1] ?? "gateway-policy-summary.json";
  if (!source) {
    console.error("Usage: gateway_policy.ts <policy.json> [summary.json]");
    Deno.exit(2);
  }
  const policy = JSON.parse(await Deno.readTextFile(source)) as GatewayPolicy;
  const summary = cloudProviderPolicySummary(policy);
  await Deno.writeTextFile(output, `${JSON.stringify(summary, null, 2)}\n`);
  console.log(JSON.stringify(summary, null, 2));
}

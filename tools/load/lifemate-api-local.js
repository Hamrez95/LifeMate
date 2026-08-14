import http from "k6/http";
import { check } from "k6";
import { Rate, Trend } from "k6/metrics";

const BASE_URL = (__ENV.BASE_URL ?? "http://127.0.0.1:54321/functions/v1/lifemate-api").replace(/\/$/, "");
const ACCESS_TOKEN = __ENV.ACCESS_TOKEN ?? "";
const PROFILE = (__ENV.LOAD_PROFILE ?? "smoke").toLowerCase();

if (!/^http:\/\/(localhost|127\.0\.0\.1)(:\d+)?(\/|$)/i.test(BASE_URL)) {
  throw new Error("This harness is intentionally local-only. Use an approved staging runner for remote capacity tests.");
}

const profiles = {
  smoke: { executor: "constant-vus", vus: 2, duration: "20s" },
  ramp: {
    executor: "ramping-arrival-rate",
    startRate: 2,
    timeUnit: "1s",
    preAllocatedVUs: 25,
    maxVUs: 150,
    stages: [
      { target: 10, duration: "20s" },
      { target: 25, duration: "30s" },
      { target: 50, duration: "30s" },
      { target: 100, duration: "30s" },
      { target: 0, duration: "20s" },
    ],
  },
};

if (!(PROFILE in profiles)) throw new Error(`Unsupported LOAD_PROFILE: ${PROFILE}`);

const unexpectedResponses = new Rate("unexpected_response_rate");
const controlledOverload = new Rate("controlled_overload_rate");
const serverErrors = new Rate("server_error_rate");
const missingCorrelationId = new Rate("missing_correlation_id_rate");
const apiLatency = new Trend("lifemate_api_latency", true);

export const options = {
  scenarios: { api: profiles[PROFILE] },
  thresholds: {
    checks: ["rate>0.99"],
    unexpected_response_rate: ["rate<0.01"],
    server_error_rate: ["rate<0.005"],
    missing_correlation_id_rate: ["rate<0.001"],
    lifemate_api_latency: ["p(95)<1500", "p(99)<3000"],
  },
};

function dateRange() {
  const now = new Date();
  return {
    from: new Date(now.getTime() - 86400000).toISOString().slice(0, 10),
    to: new Date(now.getTime() + 86400000).toISOString().slice(0, 10),
  };
}

function get(path, route) {
  const headers = { Accept: "application/json" };
  if (ACCESS_TOKEN) headers.Authorization = `Bearer ${ACCESS_TOKEN}`;
  const response = http.get(`${BASE_URL}${path}`, {
    headers,
    tags: { route },
    timeout: "10s",
  });
  const ok = response.status >= 200 && response.status < 300;
  const retryAfter =
    response.headers["Retry-After"] ?? response.headers["retry-after"] ?? "";
  const shed = response.status === 429 ||
    (response.status === 503 && retryAfter.length > 0);
  const uncontrolledServerError = response.status >= 500 && !shed;
  const correlationId =
    response.headers["X-Correlation-Id"] ??
    response.headers["x-correlation-id"] ??
    "";

  unexpectedResponses.add(!ok && !shed, { route });
  controlledOverload.add(shed, { route });
  serverErrors.add(uncontrolledServerError, { route });
  missingCorrelationId.add(correlationId.length === 0, { route });
  apiLatency.add(response.timings.duration, { route });
  check(
    response,
    {
      "success or controlled overload": () => ok || shed,
      "correlation id present": () => correlationId.length > 0,
    },
    { route },
  );
}

export default function () {
  if (!ACCESS_TOKEN) {
    get("/health", "health");
    return;
  }
  const { from, to } = dateRange();
  const bucket = (__ITER + __VU) % 10;
  if (bucket < 6) {
    get(`/api/v1/home-snapshot?fromDate=${from}&toDate=${to}`, "home-snapshot");
  } else if (bucket < 9) {
    get(`/api/v1/dose-occurrences?fromDate=${from}&toDate=${to}`, "dose-occurrences");
  } else {
    get("/api/v1/care/relationships", "care-relationships");
  }
}

export function handleSummary(data) {
  return {
    stdout: `LifeMate local load profile=${PROFILE}\n`,
    "load-summary.json": JSON.stringify(data, null, 2),
  };
}

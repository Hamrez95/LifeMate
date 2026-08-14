export const workerConsumerName = "lifemate-worker-v1";

export const supportedEvents = [
  "care.adherence_projection_refresh_requested",
  "identity.session_revoke_requested",
  "identity.account_deletion_requested",
] as const;

export function boundedWorkerBatchSize(value: string | undefined): number {
  const parsed = Number.parseInt(value ?? "20", 10);
  if (!Number.isInteger(parsed) || parsed < 1 || parsed > 50) return 20;
  return parsed;
}

export function boundedMessageTimeoutMs(value: string | undefined): number {
  const parsed = Number.parseInt(value ?? "8000", 10);
  if (!Number.isInteger(parsed) || parsed < 1000 || parsed > 20000) return 8000;
  return parsed;
}

export function retryDelaySeconds(
  eventType: string,
  attemptCount: number,
  randomValue = Math.random(),
): number {
  const base = eventType === "care.adherence_projection_refresh_requested"
    ? 10
    : 30;
  const maximum = eventType.startsWith("identity.") ? 3600 : 900;
  const exponent = Math.min(8, Math.max(0, attemptCount - 1));
  const exponential = Math.min(maximum, base * 2 ** exponent);
  const jitter = 0.75 + clamp(randomValue, 0, 1) * 0.5;
  return Math.max(1, Math.min(maximum, Math.ceil(exponential * jitter)));
}

export function isPermanentWorkerError(errorCode: string): boolean {
  return errorCode === "unsupported_event" ||
    errorCode === "aggregate_id_missing" ||
    errorCode.startsWith("invalid_") ||
    /^auth_(?:session_revoke|delete):4(?!08|09|29)\d{2}$/.test(errorCode);
}

export function queueLagLevel(
  oldestReadyAgeSeconds: number,
): "ok" | "warn" | "critical" {
  if (oldestReadyAgeSeconds >= 900) return "critical";
  if (oldestReadyAgeSeconds >= 120) return "warn";
  return "ok";
}

function clamp(value: number, minimum: number, maximum: number): number {
  if (!Number.isFinite(value)) return 0.5;
  return Math.min(maximum, Math.max(minimum, value));
}

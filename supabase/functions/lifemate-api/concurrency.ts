import { classifyRequest } from "./rate_limit.ts";
import { ApiError } from "./validation.ts";

export type ConcurrencyClass = "critical" | "expensive" | "normal";

export type ConcurrencyConfig = {
  total: number;
  nonCritical: number;
  expensive: number;
};

export type ConcurrencySnapshot = {
  total: number;
  nonCritical: number;
  expensive: number;
};

export class ConcurrencyLease {
  private released = false;

  constructor(private readonly onRelease: () => void) {}

  release(): void {
    if (this.released) return;
    this.released = true;
    this.onRelease();
  }
}

export class RequestConcurrencyGate {
  private inFlight = 0;
  private nonCriticalInFlight = 0;
  private expensiveInFlight = 0;

  constructor(private readonly config: ConcurrencyConfig) {
    validateConfig(config);
  }

  acquire(method: string, path: string): ConcurrencyLease {
    const requestClass = classifyConcurrency(method, path);

    if (this.inFlight >= this.config.total) {
      throw overloaded();
    }
    if (
      requestClass !== "critical" &&
      this.nonCriticalInFlight >= this.config.nonCritical
    ) {
      throw overloaded();
    }
    if (
      requestClass === "expensive" &&
      this.expensiveInFlight >= this.config.expensive
    ) {
      throw overloaded();
    }

    this.inFlight += 1;
    if (requestClass !== "critical") this.nonCriticalInFlight += 1;
    if (requestClass === "expensive") this.expensiveInFlight += 1;

    return new ConcurrencyLease(() => {
      this.inFlight = Math.max(0, this.inFlight - 1);
      if (requestClass !== "critical") {
        this.nonCriticalInFlight = Math.max(0, this.nonCriticalInFlight - 1);
      }
      if (requestClass === "expensive") {
        this.expensiveInFlight = Math.max(0, this.expensiveInFlight - 1);
      }
    });
  }

  snapshot(): ConcurrencySnapshot {
    return {
      total: this.inFlight,
      nonCritical: this.nonCriticalInFlight,
      expensive: this.expensiveInFlight,
    };
  }
}

export function createRequestConcurrencyGateFromEnvironment(): RequestConcurrencyGate {
  const total = positiveIntegerEnv("LIFEMATE_CONCURRENCY_TOTAL", 16);
  const nonCritical = positiveIntegerEnv(
    "LIFEMATE_CONCURRENCY_NONCRITICAL",
    12,
  );
  const expensive = positiveIntegerEnv("LIFEMATE_CONCURRENCY_EXPENSIVE", 6);

  return new RequestConcurrencyGate({ total, nonCritical, expensive });
}

export function classifyConcurrency(
  method: string,
  path: string,
): ConcurrencyClass {
  const rateClass = classifyRequest(method, path);
  if (rateClass === "critical-write") return "critical";
  if (rateClass === "expensive-read" || rateClass === "upload") {
    return "expensive";
  }
  return "normal";
}

function positiveIntegerEnv(name: string, fallback: number): number {
  const raw = Deno.env.get(name)?.trim();
  if (!raw) return fallback;
  const parsed = Number(raw);
  if (!Number.isSafeInteger(parsed) || parsed <= 0 || parsed > 10_000) {
    throw new Error(
      `${name} must be a positive integer no greater than 10000.`,
    );
  }
  return parsed;
}

function validateConfig(config: ConcurrencyConfig): void {
  for (const [name, value] of Object.entries(config)) {
    if (!Number.isSafeInteger(value) || value <= 0) {
      throw new Error(`Invalid concurrency limit: ${name}.`);
    }
  }
  if (config.nonCritical >= config.total) {
    throw new Error(
      "Non-critical concurrency must remain below total concurrency so critical requests have reserved capacity.",
    );
  }
  if (config.expensive > config.nonCritical) {
    throw new Error(
      "Expensive concurrency cannot exceed the non-critical concurrency budget.",
    );
  }
}

function overloaded(): ApiError {
  return new ApiError(
    503,
    "server_overloaded",
    "The service is temporarily busy. Please retry shortly.",
  );
}

import {
  assertEquals,
  assertThrows,
} from "jsr:@std/assert@1.0.14";
import {
  classifyConcurrency,
  RequestConcurrencyGate,
} from "./concurrency.ts";
import { ApiError } from "./validation.ts";

Deno.test("concurrency classification reserves critical adherence writes", () => {
  assertEquals(
    classifyConcurrency(
      "POST",
      "/api/v1/dose-occurrences/123e4567-e89b-42d3-a456-426614174000/report",
    ),
    "critical",
  );
  assertEquals(
    classifyConcurrency("GET", "/api/v1/home-snapshot"),
    "expensive",
  );
  assertEquals(classifyConcurrency("GET", "/api/v1/me"), "normal");
});

Deno.test("non-critical work cannot consume reserved critical capacity", () => {
  const gate = new RequestConcurrencyGate({
    total: 4,
    nonCritical: 2,
    expensive: 1,
  });
  const first = gate.acquire("GET", "/api/v1/me");
  const second = gate.acquire("GET", "/api/v1/treatment-plans");
  const error = assertThrows(
    () => gate.acquire("GET", "/api/v1/care/relationships"),
    ApiError,
  );
  assertEquals(error.status, 503);
  assertEquals(error.code, "server_overloaded");

  const critical = gate.acquire(
    "POST",
    "/api/v1/dose-occurrences/123e4567-e89b-42d3-a456-426614174000/report",
  );
  assertEquals(gate.snapshot().total, 3);

  first.release();
  second.release();
  critical.release();
  assertEquals(gate.snapshot(), { total: 0, nonCritical: 0, expensive: 0 });
});

Deno.test("expensive requests have their own smaller budget", () => {
  const gate = new RequestConcurrencyGate({
    total: 5,
    nonCritical: 4,
    expensive: 1,
  });
  const first = gate.acquire("GET", "/api/v1/home-snapshot");
  const error = assertThrows(
    () => gate.acquire("GET", "/api/v1/women-calendar/dashboard"),
    ApiError,
  );
  assertEquals(error.status, 503);
  first.release();
});

Deno.test("released capacity is immediately reusable", () => {
  const gate = new RequestConcurrencyGate({
    total: 2,
    nonCritical: 1,
    expensive: 1,
  });
  const first = gate.acquire("GET", "/api/v1/me");
  assertThrows(() => gate.acquire("GET", "/api/v1/me/profile"), ApiError);
  first.release();
  const recovered = gate.acquire("GET", "/api/v1/me/profile");
  assertEquals(gate.snapshot().total, 1);
  recovered.release();
});

Deno.test("lease release is idempotent", () => {
  const gate = new RequestConcurrencyGate({
    total: 2,
    nonCritical: 1,
    expensive: 1,
  });
  const lease = gate.acquire("GET", "/api/v1/me");
  lease.release();
  lease.release();
  assertEquals(gate.snapshot().total, 0);
});

Deno.test("invalid budgets fail closed at startup", () => {
  assertThrows(
    () =>
      new RequestConcurrencyGate({
        total: 4,
        nonCritical: 4,
        expensive: 1,
      }),
    Error,
  );
  assertThrows(
    () =>
      new RequestConcurrencyGate({
        total: 4,
        nonCritical: 3,
        expensive: 4,
      }),
    Error,
  );
});

import { buildDailyBrief } from "./daily_brief.ts";
import type { KpiValue } from "./analytics_kpi_store.ts";

function assert(condition: unknown, message: string) {
  if (!condition) throw new Error(message);
}

function series(values: number[]) {
  return values.map((value, index) => ({
    date: `2026-08-${String(index + 1).padStart(2, "0")}`,
    value,
  }));
}

Deno.test("Daily Brief derives week-over-week change only from canonical series", () => {
  const value: KpiValue = {
    name: "accounts_created",
    definitionVersion: 1,
    state: "partial",
    value: 21,
    numerator: 21,
    denominator: null,
    source: "identity.accounts.created_at_utc",
    freshness: { status: "partial", asOfUtc: "2026-08-25T22:00:00.000Z" },
    series: series([1, 1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2]),
    reason: "Relational fallback caveat.",
  };
  const brief = buildDailyBrief([value], "2026-08-25T22:30:00.000Z");
  assert(brief.changes.length === 1, "series-backed change must be emitted");
  assert(
    brief.changes[0].detail.includes("14") &&
      brief.changes[0].detail.includes("7"),
    "change must cite exact window totals",
  );
  assert(
    brief.attention.length === 1,
    "partial source must remain visible as attention",
  );
  assert(
    brief.evidence[0].source === value.source,
    "source evidence must be preserved",
  );
});

Deno.test("Daily Brief does not fabricate trends without comparable series", () => {
  const value: KpiValue = {
    name: "monthly_active_accounts",
    definitionVersion: 1,
    state: "ready",
    value: 12,
    numerator: 12,
    denominator: null,
    source: "approved activity read model",
    freshness: { status: "fresh", asOfUtc: "2026-08-25T22:00:00.000Z" },
  };
  const brief = buildDailyBrief([value], "2026-08-25T22:30:00.000Z");
  assert(brief.state === "ready", "fresh evidence must remain ready");
  assert(
    brief.changes.length === 0,
    "missing series must not produce a fabricated trend",
  );
  assert(
    brief.actions.length === 0,
    "healthy source must not invent an action",
  );
});

Deno.test("Daily Brief fails closed when no allowlisted evidence exists", () => {
  const brief = buildDailyBrief([], "2026-08-25T22:30:00.000Z");
  assert(brief.state === "unavailable", "empty source set must be unavailable");
  assert(
    brief.changes.length === 0 && brief.evidence.length === 0,
    "empty source must not fabricate evidence",
  );
  assert(brief.attention.length === 1, "unavailable state must be explicit");
});

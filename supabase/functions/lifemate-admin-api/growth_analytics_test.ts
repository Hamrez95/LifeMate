import {
  assertEquals,
  assertStringIncludes,
  assertThrows,
} from "jsr:@std/assert";
import {
  parseGrowthAnalyticsQuery,
  previousPeriod,
} from "./growth_analytics.ts";

Deno.test("growth analytics accepts canonical windows and product filter", () => {
  const query = parseGrowthAnalyticsQuery(
    new URL(
      "https://example.test/api/v1/analytics/growth?from=2026-08-01&to=2026-08-31&window=monthly&product=wellmate",
    ),
  );
  assertEquals(query, {
    from: "2026-08-01",
    to: "2026-08-31",
    window: "monthly",
    product: "wellmate",
  });
});

Deno.test("growth analytics rejects invalid calendar ranges", () => {
  assertThrows(
    () =>
      parseGrowthAnalyticsQuery(
        new URL(
          "https://example.test/api/v1/analytics/growth?from=2026-02-30&to=2026-03-01",
        ),
      ),
  );
  assertThrows(
    () =>
      parseGrowthAnalyticsQuery(
        new URL(
          "https://example.test/api/v1/analytics/growth?from=2026-08-02&to=2026-08-01",
        ),
      ),
  );
});

Deno.test("growth previous period has equal inclusive duration", () => {
  assertEquals(
    previousPeriod({
      from: "2026-08-01",
      to: "2026-08-07",
      window: "weekly",
      product: null,
    }),
    { from: "2026-07-25", to: "2026-07-31" },
  );
});

Deno.test(
  "active-user aggregate is account scoped, deduplicated and privacy bounded",
  async () => {
    const migration = await Deno.readTextFile(
      new URL(
        "../../migrations/20260903080000_growth_active_user_metrics_v1.sql",
        import.meta.url,
      ),
    );

    assertStringIncludes(migration, "count(distinct s.account_id)");
    assertStringIncludes(migration, "e.event_name = 'app_opened'");
    assertStringIncludes(migration, "e.outcome = 'success'");
    assertStringIncludes(
      migration,
      "p_product is null or e.product = lower(p_product)",
    );
    assertStringIncludes(
      migration,
      "join identity.accounts a on a.id = e.account_id",
    );
    assertStringIncludes(
      migration,
      "grant execute on function admin.read_growth_active_user_metrics_v1(date,varchar) to lifemate_admin_runtime",
    );
    assertEquals(
      /grant\s+select\s+on\s+analytics\.product_activity_events\s+to\s+lifemate_admin_runtime/i
        .test(migration),
      false,
    );
    assertEquals(
      /\b(email|phone|medication|dosage|symptom|diagnosis|cycle|pregnancy|note)\b/i
        .test(migration),
      false,
    );
  },
);

Deno.test(
  "active-user windows use Tehran calendar boundaries and no fabricated backfill",
  async () => {
    const migration = await Deno.readTextFile(
      new URL(
        "../../migrations/20260903080000_growth_active_user_metrics_v1.sql",
        import.meta.url,
      ),
    );
    const source = await Deno.readTextFile(
      new URL("./growth_analytics.ts", import.meta.url),
    );

    assertStringIncludes(
      migration,
      "p_date::timestamp at time zone 'Asia/Tehran'",
    );
    assertStringIncludes(migration, "p_date - 6");
    assertStringIncludes(migration, "p_date - 29");
    assertStringIncludes(migration, "first_event_at_utc <= b.day_start");
    assertStringIncludes(migration, "first_event_at_utc <= b.wau_start");
    assertStringIncludes(migration, "first_event_at_utc <= b.mau_start");
    assertStringIncludes(source, '"not_instrumented"');
    assertStringIncludes(source, '"not_enough_data"');
    assertStringIncludes(source, "earlier activity is not fabricated");
    assertStringIncludes(
      source,
      "from admin.read_growth_active_user_metrics_v1",
    );
    assertStringIncludes(source, "personScoped: []");
    assertStringIncludes(source, '"dau_mau_stickiness"');
    assertStringIncludes(source, '"wau_mau_stickiness"');
    assertStringIncludes(source, '"new_dau"');
    assertStringIncludes(source, '"returning_dau"');
  },
);

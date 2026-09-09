import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert";

import { getKpiValues } from "./analytics_kpi_store.ts";
import type { AdminSql } from "./database_client.ts";
import { listUserDirectory } from "./directory_store.ts";
import { getRelationshipOverview } from "./relationship_overview_store.ts";
import { listSupportQueue } from "./support_store.ts";

function captureSql() {
  const queries: string[] = [];
  const sql = ((strings: TemplateStringsArray, ..._values: unknown[]) => {
    queries.push(strings.join("?"));
    return Promise.resolve([]);
  }) as unknown as AdminSql;
  return { sql, queries };
}

async function source(name: string): Promise<string> {
  return await Deno.readTextFile(new URL(name, import.meta.url));
}

Deno.test("user directory stays on the canonical Admin read model", async () => {
  const { sql, queries } = captureSql();
  await listUserDirectory(sql, {
    page: 1,
    pageSize: 25,
    offset: 0,
    search: null,
    status: null,
    application: null,
    sort: "createdAt",
    direction: "desc",
  });

  assertEquals(queries.length, 2);
  for (const query of queries) {
    assertStringIncludes(query, "admin.user_directory_v2");
    assert(!query.includes("lifemate.user_profiles"));
    assert(!query.includes("lifemate.app_users"));
  }
});

Deno.test(
  "relationship overview keeps natural, care, consent and grants distinct",
  async () => {
    const { sql, queries } = captureSql();
    await getRelationshipOverview(sql, {
      page: 1,
      pageSize: 25,
      kind: null,
      status: null,
    });

    assertEquals(queries.length, 3);
    for (const query of queries) {
      assertStringIncludes(query, "network.person_relationships");
      assertStringIncludes(query, "admin.care_relationship_directory_v1");
      assertStringIncludes(query, "consent.consent_records");
      assertStringIncludes(query, "security.access_grants");
      assert(!query.includes("lifemate.care_relationships"));
    }
  },
);

Deno.test("support queue stays on the privacy-minimized Admin read model", async () => {
  const { sql, queries } = captureSql();
  await listSupportQueue(sql, {
    page: 1,
    pageSize: 25,
    offset: 0,
    search: null,
    status: null,
    priority: null,
    product: null,
    sla: null,
    assigneeAccountId: null,
    unassignedOnly: false,
  });

  assertEquals(queries.length, 2);
  for (const query of queries) {
    assertStringIncludes(query, "admin.support_ticket_queue_v1");
    assert(!query.includes("lifemate."));
  }
});

Deno.test("analytics KPI fallback reads canonical identity and ecosystem snapshots", async () => {
  const { sql, queries } = captureSql();
  await getKpiValues(sql, {
    from: "2026-08-01",
    to: "2026-08-24",
    product: null,
  });

  assertEquals(queries.length, 2);
  assertStringIncludes(queries[0], "identity.accounts");
  assertStringIncludes(queries[1], "identity.accounts");
  for (const query of queries) {
    assert(!query.includes("lifemate.app_users"));
    assert(!query.includes("lifemate.user_profiles"));
  }
});

Deno.test("commerce overview remains on the canonical commerce schema", async () => {
  const text = await source("./commerce_service.ts");
  assertStringIncludes(text, "commerce.subscriptions");
  assertStringIncludes(text, "commerce.entitlements");
  assertStringIncludes(text, "commerce.products");
  assert(!text.includes("lifemate."));
});

Deno.test("commerce promotion metadata is RLS-protected for restricted Admin reads", async () => {
  const migration = await Deno.readTextFile(
    new URL(
      "../../migrations/20260830003000_enable_commerce_promotion_rls.sql",
      import.meta.url,
    ),
  );
  assertStringIncludes(
    migration,
    "alter table commerce.promotions enable row level security",
  );
  assertStringIncludes(
    migration,
    "alter table commerce.discount_codes enable row level security",
  );
  assertStringIncludes(migration, "to lifemate_admin_runtime");
  assertStringIncludes(migration, "for select");
  assertStringIncludes(
    migration,
    "revoke all on table commerce.promotions from public",
  );
  assertStringIncludes(
    migration,
    "revoke all on table commerce.discount_codes from public",
  );
  assertStringIncludes(migration, "to_regrole('anon') is not null");
  assertStringIncludes(migration, "to_regrole('authenticated') is not null");
  assertStringIncludes(
    migration,
    "execute 'revoke all on table commerce.promotions from anon'",
  );
  assertStringIncludes(
    migration,
    "execute 'revoke all on table commerce.discount_codes from authenticated'",
  );
  assert(!migration.includes("to authenticated\nusing (true)"));
  assert(!migration.includes("to anon\nusing (true)"));
});

Deno.test("marketing campaigns stay on bounded Admin read/write models", async () => {
  const text = await source("./marketing_campaigns_store.ts");
  assertStringIncludes(text, "admin.marketing_campaigns_v1");
  assertStringIncludes(text, "admin.create_marketing_campaign");
  assertStringIncludes(text, "admin.update_marketing_campaign");
  assert(!text.includes("lifemate."));
});

Deno.test("finance actuals and budget remain on the canonical finance schema", async () => {
  const actual = await source("./finance_service.ts");
  const budget = await source("./finance_budget_service.ts");
  assertStringIncludes(actual, "finance.actual_ledger_entries");
  assertStringIncludes(budget, "finance.");
  assert(!actual.includes("lifemate."));
  assert(!budget.includes("lifemate."));
});

Deno.test("security RBAC remains isolated to the Admin authorization domain", async () => {
  const matrix = await source("./security_rbac_service.ts");
  const detail = await source("./security_role_detail_service.ts");
  assertStringIncludes(matrix, "admin.roles");
  assertStringIncludes(matrix, "admin.permissions");
  assertStringIncludes(matrix, "admin.role_permissions");
  assertStringIncludes(detail, "admin.");
  assert(!matrix.includes("lifemate."));
  assert(!detail.includes("lifemate."));
});

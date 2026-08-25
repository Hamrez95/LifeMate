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

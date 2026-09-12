import { assertEquals, assertFalse } from "jsr:@std/assert";

import { groupUserRelationshipRows } from "./user_detail_relationships.ts";

Deno.test("preserves counterpart-safe relationship records", () => {
  const result = groupUserRelationshipRows([
    {
      relationship_id: "10000000-0000-4000-8000-000000000001",
      relationship_source: "person_relationship",
      direction: "Outgoing",
      relationship_type: "Partner",
      status: "Active",
      counterpart_person_id: "20000000-0000-4000-8000-000000000001",
      counterpart_account_id: "30000000-0000-4000-8000-000000000001",
      counterpart_display_name: "Safe display",
      counterpart_username: "safe_user",
      created_at_utc: new Date("2026-08-01T10:00:00Z"),
      ended_at_utc: null,
    },
    {
      relationship_id: "10000000-0000-4000-8000-000000000002",
      relationship_source: "person_relationship",
      direction: "Outgoing",
      relationship_type: "Partner",
      status: "Active",
      counterpart_person_id: "20000000-0000-4000-8000-000000000002",
      counterpart_account_id: null,
      counterpart_display_name: null,
      counterpart_username: null,
      created_at_utc: "2026-08-02T10:00:00.000Z",
      ended_at_utc: null,
    },
    {
      relationship_id: "40000000-0000-4000-8000-000000000001",
      relationship_source: "care_relationship",
      direction: "Incoming",
      relationship_type: "CareRecipient",
      status: "Revoked",
      counterpart_person_id: "50000000-0000-4000-8000-000000000001",
      counterpart_account_id: "60000000-0000-4000-8000-000000000001",
      counterpart_display_name: "Care recipient",
      counterpart_username: null,
      created_at_utc: "2026-07-01T10:00:00.000Z",
      ended_at_utc: "2026-07-20T10:00:00.000Z",
    },
  ]);

  assertEquals(result.length, 2);
  assertEquals(result[0].count, 2);
  assertEquals(result[0].records[0].counterpartDisplayName, "Safe display");
  assertEquals(result[0].records[0].counterpartUsername, "safe_user");
  assertEquals(result[1].records[0].source, "care_relationship");
  assertEquals(
    result[1].records[0].endedAtUtc,
    "2026-07-20T10:00:00.000Z",
  );

  const serialized = JSON.stringify(result).toLowerCase();
  for (const forbidden of ["phone", "email", "consent", "accessgrant", "health"]) {
    assertFalse(
      serialized.includes(forbidden),
      `relationship response leaked ${forbidden}`,
    );
  }
});

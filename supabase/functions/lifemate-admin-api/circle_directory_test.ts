import {
  assert,
  assertEquals,
  assertThrows,
} from "jsr:@std/assert";

import {
  matchAdminCircleDetailPath,
  parseAdminCircleListQuery,
} from "./circle_directory.ts";

const OWNER_ID = "11111111-1111-4111-8111-111111111111";
const MEMBER_ID = "22222222-2222-4222-8222-222222222222";
const CIRCLE_ID = "33333333-3333-4333-8333-333333333333";

Deno.test("Circle directory parser accepts only bounded structural filters", () => {
  const url = new URL(
    `https://admin.invalid/api/v1/circles?page=2&pageSize=50&status=active&kind=family&ownerPersonId=${OWNER_ID}&memberPersonId=${MEMBER_ID}&q=Family`,
  );
  assertEquals(parseAdminCircleListQuery(url), {
    page: 2,
    pageSize: 50,
    status: "active",
    kind: "family",
    ownerPersonId: OWNER_ID,
    memberPersonId: MEMBER_ID,
    q: "Family",
  });
});

Deno.test("Circle directory parser rejects unsupported or unsafe filter shapes", () => {
  assertThrows(() =>
    parseAdminCircleListQuery(
      new URL("https://admin.invalid/api/v1/circles?kind=medical_records"),
    )
  );
  assertThrows(() =>
    parseAdminCircleListQuery(
      new URL("https://admin.invalid/api/v1/circles?pageSize=101"),
    )
  );
  assertThrows(() =>
    parseAdminCircleListQuery(
      new URL("https://admin.invalid/api/v1/circles?ownerPersonId=not-a-uuid"),
    )
  );
  assertThrows(() =>
    parseAdminCircleListQuery(
      new URL("https://admin.invalid/api/v1/circles?q=x"),
    )
  );
});

Deno.test("Circle detail matcher accepts one canonical UUID segment", () => {
  assertEquals(
    matchAdminCircleDetailPath(`/api/v1/circles/${CIRCLE_ID}`),
    CIRCLE_ID,
  );
  assertEquals(matchAdminCircleDetailPath("/api/v1/circles"), null);
  assertThrows(() =>
    matchAdminCircleDetailPath("/api/v1/circles/not-a-uuid")
  );
});

Deno.test("Circle Admin read-model remains structure-only", async () => {
  const store = await Deno.readTextFile(
    new URL("./circle_directory_store.ts", import.meta.url),
  );
  const routes = await Deno.readTextFile(
    new URL("./circle_directory_routes.ts", import.meta.url),
  );
  const migration = await Deno.readTextFile(
    new URL(
      "../../migrations/20260831104000_admin_circle_structure_read.sql",
      import.meta.url,
    ),
  );

  assert(routes.includes('requirePermission(admin, "relationships.read")'));
  assert(routes.includes('scope: "structure_only"'));
  assert(routes.includes("protectedHealthContentIncluded: false"));

  for (const prohibited of [
    "invitee_contact_hash",
    "circle_planning_events",
    "circle_audit_events",
    "gender_identity",
    "sex_assigned_at_birth",
    "fertility",
    "symptom",
    "pain",
    "private_note",
  ]) {
    assert(
      !store.includes(prohibited),
      `Circle Admin store must not read protected field/table: ${prohibited}`,
    );
  }

  for (const allowedTable of [
    "network.circles",
    "network.circle_members",
    "network.circle_invitations",
    "network.circle_member_sharing_policies",
  ]) {
    assert(migration.includes(`on table ${allowedTable} to lifemate_admin_runtime`));
  }
  assert(!migration.includes("grant select on table network.circles"));
  assert(!migration.includes("grant select on table network.circle_members"));
  assert(!migration.includes("grant select on table network.circle_invitations"));
  assert(!migration.includes("grant select on table network.circle_member_sharing_policies"));
  assert(!migration.includes("grant select on table network.circle_planning_events"));
  assert(!migration.includes("grant select on table network.circle_audit_events"));

  const invitationGrant = migration.slice(
    migration.indexOf("grant select (\n  id,\n  circle_id,\n  inviter_person_id"),
    migration.indexOf(
      ") on table network.circle_invitations to lifemate_admin_runtime;",
    ),
  );
  assert(invitationGrant.length > 0);
  assert(!invitationGrant.includes("invitee_contact_hash"));

  const sharingGrant = migration.slice(
    migration.indexOf("grant select (\n  circle_id,\n  person_id,\n  sharing_mode"),
    migration.indexOf(
      ") on table network.circle_member_sharing_policies to lifemate_admin_runtime;",
    ),
  );
  assert(sharingGrant.length > 0);
  assert(!sharingGrant.includes("include_period_window"));
  assert(!sharingGrant.includes("include_phase_context"));
  assert(!sharingGrant.includes("include_wellbeing_context"));
});

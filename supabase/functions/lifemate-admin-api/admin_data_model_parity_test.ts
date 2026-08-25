import { assert, assertStringIncludes } from "jsr:@std/assert";

async function source(path: string): Promise<string> {
  return await Deno.readTextFile(new URL(path, import.meta.url));
}

Deno.test("user directory stays on the canonical Admin read model", async () => {
  const directory = await source("./directory_store.ts");

  assertStringIncludes(directory, "from admin.user_directory_v2");
  assert(!directory.includes("lifemate.user_profiles"));
  assert(!directory.includes("lifemate.app_users"));
  assert(!directory.includes("identity.accounts a"));
});

Deno.test(
  "relationship overview keeps natural and care relationships semantically distinct",
  async () => {
    const relationships = await source("./relationship_overview_store.ts");

    assertStringIncludes(relationships, "from network.person_relationships");
    assertStringIncludes(
      relationships,
      "from admin.care_relationship_directory_v1",
    );
    assertStringIncludes(relationships, "from consent.consent_records");
    assertStringIncludes(relationships, "from security.access_grants");
    assert(!relationships.includes("from lifemate.care_relationships"));
  },
);

Deno.test(
  "care relationship compatibility view cannot fabricate a natural relationship row",
  async () => {
    const migration = await Deno.readTextFile(
      new URL(
        "../../migrations/20260825151000_add_admin_care_relationship_directory.sql",
        import.meta.url,
      ),
    );

    assertStringIncludes(
      migration,
      "create or replace view admin.care_relationship_directory_v1",
    );
    assertStringIncludes(
      migration,
      "from lifemate.care_relationships relationship",
    );
    assert(!migration.includes("insert into network.person_relationships"));
  },
);

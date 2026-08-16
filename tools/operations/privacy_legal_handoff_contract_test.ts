import { assert, assertEquals } from "jsr:@std/assert@1.0.14";

const repoRoot = new URL("../../", import.meta.url);

async function read(path: string): Promise<string> {
  return await Deno.readTextFile(new URL(path, repoRoot));
}

Deno.test(
  "closed-beta legal handoff stays bound to fail-closed consent and open human approval",
  async () => {
    const handoff = await read("docs/privacy/CLOSED_BETA_PRIVACY_REVIEW.md");
    const consentModel = await read("docs/privacy/consent-model.md");
    const secondaryUse = await read("docs/privacy/secondary-data-use.md");
    const authorization = await read(
      "supabase/migrations/20260806231133_authorization_entitlement_policy_20260807.sql",
    );

    for (
      const phrase of [
        "ENGINEERING REVIEW COMPLETE / HUMAN LEGAL APPROVAL OPEN",
        "relationship alone is never permission",
        "HIGHLY SENSITIVE",
        "raw authentication/provider subjects",
        "Commercial/pharmaceutical analytics is **DISABLED by default**",
        "OPEN / BLOCKING",
        "CI **cannot** change any row below to Approved",
        "Foundation #214 remains OPEN",
      ]
    ) {
      assert(handoff.includes(phrase), `legal handoff is missing: ${phrase}`);
    }

    assert(
      consentModel.includes(
        "Relationship, authorization, entitlement and consent are separate facts.",
      ),
    );
    assert(
      consentModel.includes(
        "Absence of a positive, current record is denial.",
      ),
    );
    assert(
      secondaryUse.includes(
        "Commercial/pharmaceutical analytics is **DISABLED by default**",
      ),
    );
    assert(
      secondaryUse.includes("raw user-level health records, identity/PII"),
    );

    assert(authorization.includes("security.can_access_person_feature"));
    assert(authorization.includes("and c.status='Granted'"));
    assert(
      authorization.includes(
        "v_status := case when new.status='Active' then 'Granted' else 'Revoked' end",
      ),
    );

    assertEquals(handoff.includes("legal approval is complete"), false);
    assertEquals(
      handoff.includes("relationship automatically grants access"),
      false,
    );
  },
);

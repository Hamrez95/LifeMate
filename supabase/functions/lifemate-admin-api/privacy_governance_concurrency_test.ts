import { assert, assertStringIncludes } from "jsr:@std/assert@1";

Deno.test("legal document publication is serialized per purpose and jurisdiction", async () => {
  const sql = await Deno.readTextFile(
    "../../migrations/20260828022500_legal_document_publish_serialization.sql",
  );

  assertStringIncludes(sql, "pg_advisory_xact_lock");
  assertStringIncludes(sql, "new.purpose || ':' || new.jurisdiction");
  assertStringIncludes(sql, "new.purpose not in ('legal_terms','privacy_notice')");
  assertStringIncludes(sql, "set status = 'Retired'");
  assertStringIncludes(sql, "before insert or update of status, purpose, jurisdiction");
  assertStringIncludes(sql, "execute function consent.serialize_active_legal_document()");

  const retirePredicate = /where purpose = new\.purpose[\s\S]*jurisdiction = new\.jurisdiction[\s\S]*status = 'Active'[\s\S]*id <> new\.id/;
  assert(retirePredicate.test(sql));
});

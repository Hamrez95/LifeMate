import { assertEquals } from "jsr:@std/assert@1.0.14";
import {
  isOwnerOnlyPregnancyScope,
  isPregnancyScope,
  pregnancyScopes,
} from "./pregnancy_authorization.ts";

Deno.test("pregnancy scope catalog is explicit and has no broad all scope", () => {
  assertEquals(pregnancyScopes.includes("pregnancy.summary.read"), true);
  assertEquals(pregnancyScopes.includes("pregnancy.support.write"), true);
  assertEquals(pregnancyScopes.includes("pregnancy.owner.manage"), true);
  assertEquals(isPregnancyScope("pregnancy.all"), false);
  assertEquals(isPregnancyScope("women_health.summary.read"), false);
});

Deno.test("pregnancy owner management remains distinguishable as owner-only", () => {
  assertEquals(isOwnerOnlyPregnancyScope("pregnancy.owner.manage"), true);
  assertEquals(isOwnerOnlyPregnancyScope("pregnancy.summary.read"), false);
});

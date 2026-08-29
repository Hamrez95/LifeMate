import { assertEquals, assertThrows } from "jsr:@std/assert@1";
import {
  normalizeRelationshipPresentationPatch,
  normalizeRelationshipType,
  presentationUpdateColumns,
  presentRelationshipForViewer,
  relationshipPresentationCopyVersion,
} from "./relationship_presentation.ts";

const patientPersonId = "00000000-0000-4000-8000-000000000001";
const caregiverPersonId = "00000000-0000-4000-8000-000000000002";

const row = () => ({
  patient_person_id: patientPersonId,
  caregiver_person_id: caregiverPersonId,
  patient_display_name: "Hamidreza",
  caregiver_display_name: "Maryam",
  caregiver_patient_display_name: "پسرم",
  patient_caregiver_display_name: "مامان جون",
  relationship_type: "family",
  caregiver_relationship_type: "family",
  patient_relationship_type: "family",
  can_view_women_calendar: false,
});

Deno.test("relationship types collapse to partner family child with legacy compatibility", () => {
  assertEquals(normalizeRelationshipType("spouse"), "partner");
  assertEquals(normalizeRelationshipType("child_caring_for_parent"), "child");
  assertEquals(normalizeRelationshipType("trusted_caregiver"), "family");
  assertEquals(normalizeRelationshipType("parent_caring_for_dependent"), "family");
  assertEquals(normalizeRelationshipType("doctor"), "unknown");
});

Deno.test("presentation patch canonicalizes legacy type and trims alias", () => {
  assertEquals(
    normalizeRelationshipPresentationPatch({
      relationshipType: "child-caring-for-parent",
      displayName: "  پسرم  ",
    }),
    { relationshipType: "child", displayName: "پسرم" },
  );
  assertThrows(() =>
    normalizeRelationshipPresentationPatch({
      relationshipType: "doctor",
      displayName: "Doctor",
    })
  );
});

Deno.test("caregiver sees caregiver-owned nickname with canonical relation", () => {
  const value = presentRelationshipForViewer(row(), caregiverPersonId);
  assertEquals(value.patientDisplayName, "پسرم");
  assertEquals(value.patientOfficialDisplayName, "Hamidreza");
  assertEquals(value.caregiverDisplayName, "Maryam");
  assertEquals(value.relationshipType, "family");
  assertEquals(value.presentationType, "family");
  assertEquals(value.presentationCopyVersion, relationshipPresentationCopyVersion);
});

Deno.test("owner sees owner-owned caregiver nickname independently", () => {
  const value = presentRelationshipForViewer(row(), patientPersonId);
  assertEquals(value.patientDisplayName, "Hamidreza");
  assertEquals(value.caregiverDisplayName, "مامان جون");
  assertEquals(value.caregiverOfficialDisplayName, "Maryam");
  assertEquals(value.relationshipType, "family");
});

Deno.test("caregiver alias mutation cannot overwrite canonical admin relationship type", () => {
  const columns = presentationUpdateColumns("caregiver", {
    relationshipType: "family",
    displayName: "پسرم",
  });
  assertEquals(columns, {
    caregiver_relationship_type: "family",
    caregiver_patient_display_name: "پسرم",
  });
  assertEquals(Object.hasOwn(columns, "relationship_type"), false);
});

Deno.test("owner presentation columns include canonical reportable relationship type", () => {
  const columns = presentationUpdateColumns("patient", {
    relationshipType: "partner",
    displayName: "عزیزم",
  });
  assertEquals(columns, {
    relationship_type: "partner",
    patient_relationship_type: "partner",
    patient_caregiver_display_name: "عزیزم",
  });
  const keys = Object.keys(columns).join(" ");
  assertEquals(/permission|consent|can_view|scope|notification/i.test(keys), false);
});

Deno.test("presentation mutation remains isolated from authorization", async () => {
  const source = await Deno.readTextFile("person_care_relationship_management.ts");
  const start = source.indexOf("async function updateRelationshipPresentation(");
  const end = source.indexOf("async function updateRelationshipPermissions(", start);
  if (start < 0 || end <= start) throw new Error("presentation mutation block missing");
  const block = source.slice(start, end);

  assertEquals(block.includes("relationship_type"), true);
  assertEquals(block.includes("caregiver_patient_display_name"), true);
  assertEquals(block.includes("patient_caregiver_display_name"), true);
  assertEquals(/can_view|privacy_scope|permission/i.test(block), false);
});

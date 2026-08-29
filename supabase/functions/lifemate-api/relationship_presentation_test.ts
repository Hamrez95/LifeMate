import { assertEquals, assertThrows } from "jsr:@std/assert@1";
import {
  normalizeRelationshipPresentationPatch,
  presentationUpdateColumns,
  presentRelationshipForViewer,
  relationshipPresentationCopyVersion,
} from "./relationship_presentation.ts";

const patientPersonId = "00000000-0000-4000-8000-000000000001";
const caregiverPersonId = "00000000-0000-4000-8000-000000000002";

const row = () => ({
  patient_person_id: patientPersonId,
  caregiver_person_id: caregiverPersonId,
  patient_display_name: "Maryam Ahmadi",
  caregiver_display_name: "Ali Ahmadi",
  caregiver_patient_display_name: "Mum",
  patient_caregiver_display_name: "Ali jan",
  caregiver_relationship_type: "child_caring_for_parent",
  patient_relationship_type: "family",
  can_view_women_calendar: false,
});

Deno.test("presentation patch validates independent type and display alias", () => {
  assertEquals(
    normalizeRelationshipPresentationPatch({
      relationshipType: "child-caring-for-parent",
      displayName: "  Mum  ",
    }),
    {
      relationshipType: "child_caring_for_parent",
      displayName: "Mum",
    },
  );
  assertThrows(() =>
    normalizeRelationshipPresentationPatch({
      relationshipType: "doctor",
      displayName: "Doctor",
    })
  );
});

Deno.test("caregiver sees only caregiver-owned alias and presentation type", () => {
  const value = presentRelationshipForViewer(row(), caregiverPersonId);
  assertEquals(value.patientDisplayName, "Mum");
  assertEquals(value.caregiverDisplayName, "Ali Ahmadi");
  assertEquals(value.presentationType, "child_caring_for_parent");
  assertEquals(value.presentationCopyVersion, relationshipPresentationCopyVersion);
  assertEquals(value.patientOfficialDisplayName, "Maryam Ahmadi");
});

Deno.test("patient sees only patient-owned caregiver alias and presentation type", () => {
  const value = presentRelationshipForViewer(row(), patientPersonId);
  assertEquals(value.patientDisplayName, "Maryam Ahmadi");
  assertEquals(value.caregiverDisplayName, "Ali jan");
  assertEquals(value.presentationType, "family");
  assertEquals(value.caregiverOfficialDisplayName, "Ali Ahmadi");
});

Deno.test("presentation update columns cannot mutate permissions or consent", () => {
  const columns = presentationUpdateColumns("caregiver", {
    relationshipType: "partner",
    displayName: "Sara",
  });
  assertEquals(columns, {
    caregiver_relationship_type: "partner",
    caregiver_patient_display_name: "Sara",
  });
  const keys = Object.keys(columns).join(" ");
  assertEquals(/permission|consent|can_view|scope|notification/i.test(keys), false);
});

Deno.test("unknown stored presentation falls back to neutral type", () => {
  const value = presentRelationshipForViewer(
    { ...row(), caregiver_relationship_type: "legacy_unknown" },
    caregiverPersonId,
  );
  assertEquals(value.presentationType, "unknown");
});

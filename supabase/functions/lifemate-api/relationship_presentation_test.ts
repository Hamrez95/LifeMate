import { assertEquals, assertThrows } from "jsr:@std/assert@1";
import {
  circleAccessPresentationValues,
  normalizeRelationshipPresentationPatch,
  normalizeRelationshipType,
  presentationUpdateColumns,
  presentRelationshipForViewer,
  relationshipPresentationCopyVersion,
  relationshipPresentationTypes,
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
  status: "Active",
  patient_consented_at_utc: new Date("2026-09-01T10:00:00Z"),
  caregiver_consented_at_utc: new Date("2026-09-01T10:01:00Z"),
  revoked_at_utc: null,
  can_view_women_calendar: false,
});

Deno.test("relationship taxonomy supports legacy and expanded canonical categories", () => {
  const cases: Array<[string, string]> = [
    ["spouse", "partner"],
    ["child_caring_for_parent", "child"],
    ["parent_caring_for_dependent", "family"],
    ["friend", "friend"],
    ["trusted_caregiver", "trusted_person"],
    ["physician", "doctor"],
    ["nurse", "nurse"],
    ["caregiver", "professional_caregiver"],
    ["professional caregiver", "professional_caregiver"],
    ["therapist", "therapist_specialist"],
    ["specialist", "therapist_specialist"],
    ["other", "other"],
  ];
  for (const [raw, canonical] of cases) {
    assertEquals(normalizeRelationshipType(raw), canonical);
    assertEquals(relationshipPresentationTypes.has(canonical), true);
  }
});

Deno.test("presentation patch accepts canonical professional role and trims alias", () => {
  assertEquals(
    normalizeRelationshipPresentationPatch({
      relationshipType: "professional-caregiver",
      displayName: "  مراقب من  ",
    }),
    { relationshipType: "professional_caregiver", displayName: "مراقب من" },
  );
  assertThrows(() =>
    normalizeRelationshipPresentationPatch({
      relationshipType: "unsupported-role",
      displayName: "Unknown",
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
  assertEquals(value.viewerRole, "caregiver");
  assertEquals(value.counterpartDisplayName, "پسرم");
  assertEquals(value.circleAccessPresentation, "connected");
  assertEquals(value.campPresentationEligible, true);
  assertEquals(
    value.presentationCopyVersion,
    relationshipPresentationCopyVersion,
  );
});

Deno.test("owner sees owner-owned caregiver nickname independently", () => {
  const value = presentRelationshipForViewer(row(), patientPersonId);
  assertEquals(value.patientDisplayName, "Hamidreza");
  assertEquals(value.caregiverDisplayName, "مامان جون");
  assertEquals(value.caregiverOfficialDisplayName, "Maryam");
  assertEquals(value.relationshipType, "family");
  assertEquals(value.viewerRole, "patient");
  assertEquals(value.counterpartDisplayName, "مامان جون");
  assertEquals(value.circleAccessPresentation, "connected");
  assertEquals(value.campPresentationEligible, true);
});

Deno.test("missing mutual consent degrades to permission required", () => {
  const pendingConsent = {
    ...row(),
    caregiver_consented_at_utc: null,
  };
  const value = presentRelationshipForViewer(pendingConsent, patientPersonId);
  assertEquals(value.circleAccessPresentation, "permission_required");
  assertEquals(value.campPresentationEligible, false);
  assertEquals(
    circleAccessPresentationValues.has(String(value.circleAccessPresentation)),
    true,
  );
});

Deno.test("revoked relationship is unavailable without exposing revocation detail", () => {
  const revoked = {
    ...row(),
    status: "Revoked",
    revoked_at_utc: new Date("2026-09-10T08:00:00Z"),
  };
  const value = presentRelationshipForViewer(revoked, caregiverPersonId);
  assertEquals(value.circleAccessPresentation, "access_unavailable");
  assertEquals(value.campPresentationEligible, false);
  assertEquals(Object.hasOwn(value, "revocationReason"), false);
});

Deno.test("viewer outside relationship fails closed", () => {
  const value = presentRelationshipForViewer(
    row(),
    "00000000-0000-4000-8000-000000000099",
  );
  assertEquals(value.viewerRole, "unknown");
  assertEquals(value.counterpartDisplayName, null);
  assertEquals(value.circleAccessPresentation, "access_unavailable");
  assertEquals(value.campPresentationEligible, false);
});

Deno.test("caregiver alias mutation cannot overwrite canonical admin relationship type", () => {
  const columns = presentationUpdateColumns("caregiver", {
    relationshipType: "doctor",
    displayName: "دکتر من",
  });
  assertEquals(columns, {
    caregiver_relationship_type: "doctor",
    caregiver_patient_display_name: "دکتر من",
  });
  assertEquals(Object.hasOwn(columns, "relationship_type"), false);
});

Deno.test("owner presentation columns are reportable metadata only", () => {
  const columns = presentationUpdateColumns("patient", {
    relationshipType: "trusted_person",
    displayName: "دوست من",
  });
  assertEquals(columns, {
    relationship_type: "trusted_person",
    patient_relationship_type: "trusted_person",
    patient_caregiver_display_name: "دوست من",
  });
  const keys = Object.keys(columns).join(" ");
  assertEquals(
    /permission|consent|can_view|scope|notification/i.test(keys),
    false,
  );
});

Deno.test("presentation mutation remains isolated from authorization", async () => {
  const source = await Deno.readTextFile(
    "person_care_relationship_management.ts",
  );
  const start = source.indexOf(
    "async function updateRelationshipPresentation(",
  );
  const end = source.indexOf(
    "async function updateRelationshipPermissions(",
    start,
  );
  if (start < 0 || end <= start) {
    throw new Error("presentation mutation block missing");
  }
  const block = source.slice(start, end);

  assertEquals(block.includes("relationship_type"), true);
  assertEquals(block.includes("caregiver_patient_display_name"), true);
  assertEquals(block.includes("patient_caregiver_display_name"), true);
  assertEquals(/can_view|privacy_scope|permission/i.test(block), false);
});

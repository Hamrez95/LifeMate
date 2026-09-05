import { ApiError } from "./validation.ts";

type Row = Record<string, any>;

export const relationshipPresentationCopyVersion =
  "relationship-presentation-v3";

export const relationshipPresentationTypes = new Set([
  "partner",
  "family",
  "child",
  "friend",
  "trusted_person",
  "doctor",
  "nurse",
  "professional_caregiver",
  "therapist_specialist",
  "other",
  "unknown",
]);

export type RelationshipPresentationPatch = {
  relationshipType: string;
  displayName: string | null;
};

export function normalizeRelationshipType(value: unknown): string {
  const normalized = String(value ?? "")
    .trim()
    .toLowerCase()
    .replaceAll("-", "_")
    .replaceAll(" ", "_");

  if (normalized === "partner" || normalized === "spouse") return "partner";
  if (
    normalized === "child" ||
    normalized === "child_caring_for_parent" ||
    normalized === "child_to_parent"
  ) return "child";
  if (
    normalized === "family" ||
    normalized === "family_member" ||
    normalized === "parent_caring_for_dependent" ||
    normalized === "parent_to_child" ||
    normalized === "parent_to_dependent"
  ) return "family";
  if (normalized === "friend") return "friend";
  if (
    normalized === "trusted_person" ||
    normalized === "trusted_contact" ||
    normalized === "trusted_caregiver"
  ) return "trusted_person";
  if (normalized === "doctor" || normalized === "physician") return "doctor";
  if (normalized === "nurse") return "nurse";
  if (
    normalized === "professional_caregiver" ||
    normalized === "caregiver" ||
    normalized === "professional_carer"
  ) return "professional_caregiver";
  if (
    normalized === "therapist" ||
    normalized === "specialist" ||
    normalized === "therapist_specialist"
  ) return "therapist_specialist";
  if (normalized === "other") return "other";
  return "unknown";
}

export function normalizeRelationshipPresentationPatch(
  body: Record<string, unknown>,
): RelationshipPresentationPatch {
  const relationshipType = normalizeRelationshipType(body.relationshipType);
  if (
    relationshipType === "unknown" &&
    String(body.relationshipType ?? "").trim().toLowerCase() !== "unknown"
  ) {
    throw new ApiError(
      400,
      "invalid_relationship_presentation_type",
      "Relationship presentation type is unsupported.",
    );
  }

  const rawDisplayName = body.displayName;
  if (rawDisplayName != null && typeof rawDisplayName !== "string") {
    throw new ApiError(
      400,
      "invalid_relationship_display_name",
      "Relationship display name must be text or null.",
    );
  }
  const displayName = typeof rawDisplayName === "string"
    ? rawDisplayName.trim()
    : null;
  if (displayName != null && displayName.length > 80) {
    throw new ApiError(
      400,
      "invalid_relationship_display_name",
      "Relationship display name must be 80 characters or fewer.",
    );
  }

  return {
    relationshipType,
    displayName: displayName == null || displayName.length === 0
      ? null
      : displayName,
  };
}

export function presentRelationshipForViewer(
  row: Row,
  viewerPersonId: string,
): Record<string, unknown> {
  const patientPersonId = String(row.patient_person_id ?? "");
  const caregiverPersonId = String(row.caregiver_person_id ?? "");
  const viewerIsCaregiver = viewerPersonId === caregiverPersonId;
  const viewerIsPatient = viewerPersonId === patientPersonId;

  const patientOfficial = text(row.patient_display_name) ?? "LifeMate User";
  const caregiverOfficial = text(row.caregiver_display_name) ?? "LifeMate User";
  const caregiverPatientAlias = text(row.caregiver_patient_display_name);
  const patientCaregiverAlias = text(row.patient_caregiver_display_name);
  const canonicalType = normalizeRelationshipType(
    row.relationship_type ??
      (viewerIsCaregiver
        ? row.caregiver_relationship_type
        : row.patient_relationship_type),
  );

  return {
    patientDisplayName: viewerIsCaregiver
      ? caregiverPatientAlias ?? patientOfficial
      : patientOfficial,
    caregiverDisplayName: viewerIsPatient
      ? patientCaregiverAlias ?? caregiverOfficial
      : caregiverOfficial,
    patientOfficialDisplayName: patientOfficial,
    caregiverOfficialDisplayName: caregiverOfficial,
    relationshipType: canonicalType,
    presentationType: canonicalType,
    presentationCopyVersion: relationshipPresentationCopyVersion,
  };
}

export function presentationUpdateColumns(
  role: "caregiver" | "patient",
  patch: RelationshipPresentationPatch,
): Record<string, string | null> {
  if (role === "caregiver") {
    return {
      caregiver_relationship_type: patch.relationshipType,
      caregiver_patient_display_name: patch.displayName,
    };
  }
  return {
    relationship_type: patch.relationshipType,
    patient_relationship_type: patch.relationshipType,
    patient_caregiver_display_name: patch.displayName,
  };
}

function text(value: unknown): string | null {
  const normalized = value == null ? "" : String(value).trim();
  return normalized.length === 0 ? null : normalized;
}

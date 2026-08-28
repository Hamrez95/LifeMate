import { ApiError } from "./validation.ts";

type Row = Record<string, any>;

export const relationshipPresentationCopyVersion = "relationship-presentation-v1";

export const relationshipPresentationTypes = new Set([
  "partner",
  "child_caring_for_parent",
  "parent_caring_for_dependent",
  "family",
  "trusted_caregiver",
  "unknown",
]);

export type RelationshipPresentationPatch = {
  relationshipType: string;
  displayName: string | null;
};

export function normalizeRelationshipPresentationPatch(
  body: Record<string, unknown>,
): RelationshipPresentationPatch {
  const relationshipType = String(body.relationshipType ?? "")
    .trim()
    .toLowerCase()
    .replaceAll("-", "_");
  if (!relationshipPresentationTypes.has(relationshipType)) {
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

  return {
    patientDisplayName: viewerIsCaregiver
      ? caregiverPatientAlias ?? patientOfficial
      : patientOfficial,
    caregiverDisplayName: viewerIsPatient
      ? patientCaregiverAlias ?? caregiverOfficial
      : caregiverOfficial,
    patientOfficialDisplayName: patientOfficial,
    caregiverOfficialDisplayName: caregiverOfficial,
    presentationType: viewerIsCaregiver
      ? normalizedType(row.caregiver_relationship_type)
      : viewerIsPatient
      ? normalizedType(row.patient_relationship_type)
      : "unknown",
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
    patient_relationship_type: patch.relationshipType,
    patient_caregiver_display_name: patch.displayName,
  };
}

function normalizedType(value: unknown): string {
  const normalized = String(value ?? "unknown")
    .trim()
    .toLowerCase()
    .replaceAll("-", "_");
  return relationshipPresentationTypes.has(normalized) ? normalized : "unknown";
}

function text(value: unknown): string | null {
  const normalized = value == null ? "" : String(value).trim();
  return normalized.length === 0 ? null : normalized;
}

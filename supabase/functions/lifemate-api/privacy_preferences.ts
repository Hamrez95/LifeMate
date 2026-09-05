import { getLifeMateSql } from "./database_client.ts";
import { ApiError } from "./validation.ts";

type Row = Record<string, unknown>;

export type LegalAcceptanceInput = {
  documentId: string;
  documentHash: string;
};

const PURPOSE = /^[a-z][a-z0-9._-]{2,79}$/;
const DOCUMENT_HASH = /^[A-Za-z0-9:_-]{16,160}$/;
const UUID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export function legalJurisdictionFromEnvironment(): string {
  const value = (Deno.env.get("LIFEMATE_LEGAL_JURISDICTION") ?? "GLOBAL")
    .trim()
    .toUpperCase();
  if (!/^[A-Z][A-Z0-9_-]{1,15}$/.test(value)) {
    throw new Error("LIFEMATE_LEGAL_JURISDICTION is invalid.");
  }
  return value;
}

export function parseLegalAcceptances(value: unknown): LegalAcceptanceInput[] {
  if (value == null) return [];
  if (!Array.isArray(value) || value.length > 8) {
    throw new ApiError(
      400,
      "legal_acceptance_invalid",
      "legalAcceptances must be a bounded array.",
    );
  }
  const seen = new Set<string>();
  return value.map((item) => {
    if (!item || typeof item !== "object" || Array.isArray(item)) {
      throw new ApiError(
        400,
        "legal_acceptance_invalid",
        "Legal acceptance is invalid.",
      );
    }
    const row = item as Record<string, unknown>;
    const documentId = typeof row.documentId === "string"
      ? row.documentId.trim()
      : "";
    const documentHash = typeof row.documentHash === "string"
      ? row.documentHash.trim()
      : "";
    if (!UUID.test(documentId) || !DOCUMENT_HASH.test(documentHash)) {
      throw new ApiError(
        400,
        "legal_acceptance_invalid",
        "Legal acceptance is invalid.",
      );
    }
    if (seen.has(documentId)) {
      throw new ApiError(
        400,
        "legal_acceptance_duplicate",
        "Legal acceptance is duplicated.",
      );
    }
    seen.add(documentId);
    return { documentId, documentHash };
  });
}

export function parsePrivacyPreferencePayload(value: unknown): {
  purpose: string;
  enabled: boolean;
} {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new ApiError(
      400,
      "privacy_preference_invalid",
      "Privacy preference is invalid.",
    );
  }
  const row = value as Record<string, unknown>;
  const purpose = typeof row.purpose === "string"
    ? row.purpose.trim().toLowerCase()
    : "";
  if (!PURPOSE.test(purpose) || typeof row.enabled !== "boolean") {
    throw new ApiError(
      400,
      "privacy_preference_invalid",
      "Privacy preference is invalid.",
    );
  }
  return { purpose, enabled: row.enabled };
}

export function createPrivacyPreferenceStore(
  databaseUrl: string,
  jurisdiction = legalJurisdictionFromEnvironment(),
) {
  const sql = getLifeMateSql(databaseUrl);

  async function legalRequirements(): Promise<Record<string, unknown>[]> {
    const rows = await sql`
      select * from consent.current_registration_legal_documents(${jurisdiction})
    `;
    return rows.map((row) => ({
      id: String(row.id),
      purpose: String(row.purpose),
      version: String(row.version),
      jurisdiction: String(row.jurisdiction),
      title: String(row.title),
      documentHash: String(row.document_hash),
      contentUri: row.content_uri == null ? null : String(row.content_uri),
      effectiveAtUtc: new Date(String(row.effective_at_utc)).toISOString(),
    }));
  }

  async function assertAcceptancesCurrent(
    acceptances: LegalAcceptanceInput[],
  ): Promise<void> {
    const required = await legalRequirements();
    for (const document of required) {
      if (
        !acceptances.some((item) =>
          item.documentId === document.id &&
          item.documentHash === document.documentHash
        )
      ) {
        throw new ApiError(
          428,
          "legal_acceptance_required",
          "Current legal documents must be accepted before registration can complete.",
        );
      }
    }
  }

  async function finalizeRegistration(
    appUserId: string,
    acceptances: LegalAcceptanceInput[],
  ): Promise<Record<string, unknown>> {
    const rows = await sql`
      select consent.finalize_registration_legal_acceptance(
        ${appUserId}::uuid,
        ${JSON.stringify(acceptances)}::jsonb,
        'registration',
        ${jurisdiction}
      ) as result
    `;
    const result = rows[0]?.result;
    if (!result || typeof result !== "object" || Array.isArray(result)) {
      throw new ApiError(
        503,
        "registration_finalize_unavailable",
        "Registration could not be finalized.",
      );
    }
    const payload = result as Record<string, unknown>;
    if (payload.completed !== true) {
      throw new ApiError(
        428,
        "legal_acceptance_required",
        "Current legal documents must be accepted before registration can complete.",
      );
    }
    return payload;
  }

  async function registrationStatus(
    appUserId: string,
  ): Promise<Record<string, unknown>> {
    const rows = await sql`
      select consent.registration_status_for_app_user(
        ${appUserId}::uuid,
        ${jurisdiction}
      ) as result
    `;
    const result = rows[0]?.result;
    if (!result || typeof result !== "object" || Array.isArray(result)) {
      throw new ApiError(
        404,
        "registration_status_missing",
        "Registration status was not found.",
      );
    }
    return result as Record<string, unknown>;
  }

  async function requireRegistrationComplete(appUserId: string): Promise<void> {
    const status = await registrationStatus(appUserId);
    if (status.completed !== true) {
      throw new ApiError(
        428,
        "registration_incomplete",
        "Registration must be completed before this operation is available.",
      );
    }
  }

  async function preferences(appUserId: string): Promise<unknown[]> {
    const rows = await sql`
      select consent.account_privacy_preferences(
        ${appUserId}::uuid,
        ${jurisdiction}
      ) as result
    `;
    return Array.isArray(rows[0]?.result) ? rows[0].result as unknown[] : [];
  }

  async function setPreference(
    appUserId: string,
    purpose: string,
    enabled: boolean,
  ): Promise<Record<string, unknown>> {
    try {
      const rows = await sql`
        select consent.set_account_privacy_preference(
          ${appUserId}::uuid,
          ${purpose},
          ${enabled},
          'privacy_center',
          ${jurisdiction}
        ) as result
      `;
      const result = rows[0]?.result;
      if (!result || typeof result !== "object" || Array.isArray(result)) {
        throw new Error("privacy_preference_result_invalid");
      }
      return result as Row;
    } catch (error) {
      const message = String((error as Row)?.message ?? "");
      if (message.includes("privacy_preference_unknown")) {
        throw new ApiError(
          400,
          "privacy_preference_unknown",
          "Privacy preference is not supported.",
        );
      }
      if (message.includes("privacy_preference_identity_missing")) {
        throw new ApiError(
          409,
          "privacy_preference_identity_missing",
          "Privacy preference identity is not ready.",
        );
      }
      throw error;
    }
  }

  return {
    legalRequirements,
    assertAcceptancesCurrent,
    finalizeRegistration,
    registrationStatus,
    requireRegistrationComplete,
    preferences,
    setPreference,
  };
}

import { hashContactPoint } from "../_shared/contact_point_crypto.ts";
import { getLifeMateSql } from "./database_client.ts";
import { normalizeIranianMobileE164 } from "./iran_phone.ts";
import { createHmac } from "./security.ts";
import { ApiError } from "./validation.ts";

type Row = Record<string, any>;

export type GiftTargetKind = "Offer" | "Bundle";
export type AdvocacyEvidenceType =
  | "PostUrl"
  | "StoryScreenshot"
  | "TagMention"
  | "CampaignParticipation"
  | "Other";

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const referralCodePattern = /^[A-Z0-9]{8,32}$/;
const platformPattern = /^[a-z][a-z0-9._-]{1,39}$/;
const encoder = new TextEncoder();

function requiredString(
  value: unknown,
  field: string,
  maxLength: number,
): string {
  if (typeof value !== "string") {
    throw new ApiError(400, "growth_request_invalid", `${field} is invalid.`);
  }
  const normalized = value.trim();
  if (!normalized || encoder.encode(normalized).byteLength > maxLength) {
    throw new ApiError(400, "growth_request_invalid", `${field} is invalid.`);
  }
  return normalized;
}

async function sha256(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", encoder.encode(value));
  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

export function parseGiftPayload(body: Record<string, unknown>): {
  recipientPhone: string;
  targetKind: GiftTargetKind;
  targetId: string;
} {
  const rawPhone = requiredString(body.recipientPhone, "recipientPhone", 64);
  const recipientPhone = normalizeIranianMobileE164(rawPhone);
  if (!recipientPhone) {
    throw new ApiError(
      400,
      "gift_recipient_phone_invalid",
      "A valid Iranian mobile number is required.",
    );
  }
  const targetKind = requiredString(body.targetKind, "targetKind", 16);
  if (targetKind !== "Offer" && targetKind !== "Bundle") {
    throw new ApiError(400, "gift_target_invalid", "Gift target is invalid.");
  }
  const targetId = requiredString(body.targetId, "targetId", 64).toLowerCase();
  if (!uuidPattern.test(targetId)) {
    throw new ApiError(400, "gift_target_invalid", "Gift target is invalid.");
  }
  return { recipientPhone, targetKind, targetId };
}

export function parseReferralPayload(body: Record<string, unknown>): string {
  const code = requiredString(body.code, "code", 32).toUpperCase();
  if (!referralCodePattern.test(code)) {
    throw new ApiError(
      400,
      "referral_code_invalid",
      "Referral code is invalid.",
    );
  }
  return code;
}

export function parseAdvocacyPayload(body: Record<string, unknown>): {
  platformCode: string;
  evidenceType: AdvocacyEvidenceType;
  evidenceReference: string;
} {
  const platformCode = requiredString(body.platformCode, "platformCode", 40)
    .toLowerCase();
  if (!platformPattern.test(platformCode)) {
    throw new ApiError(
      400,
      "advocacy_platform_invalid",
      "Advocacy platform is invalid.",
    );
  }
  const evidenceType = requiredString(body.evidenceType, "evidenceType", 32);
  const allowed = new Set<AdvocacyEvidenceType>([
    "PostUrl",
    "StoryScreenshot",
    "TagMention",
    "CampaignParticipation",
    "Other",
  ]);
  if (!allowed.has(evidenceType as AdvocacyEvidenceType)) {
    throw new ApiError(
      400,
      "advocacy_evidence_type_invalid",
      "Advocacy evidence type is invalid.",
    );
  }
  const evidenceReference = requiredString(
    body.evidenceReference,
    "evidenceReference",
    2048,
  );
  return {
    platformCode,
    evidenceType: evidenceType as AdvocacyEvidenceType,
    evidenceReference,
  };
}

function resultStatus(result: Row, fallbackCode: string): number {
  const status = Number(result.httpStatus);
  if (!Number.isInteger(status) || status < 100 || status > 599) {
    throw new ApiError(
      503,
      fallbackCode,
      "Growth workflow returned an invalid status.",
    );
  }
  return status;
}

function requireSuccessful(result: Row, fallbackCode: string): Row {
  const status = resultStatus(result, fallbackCode);
  if (status >= 400) {
    throw new ApiError(
      status,
      typeof result.code === "string" ? result.code : fallbackCode,
      typeof result.message === "string"
        ? result.message
        : "Growth workflow was not completed.",
    );
  }
  return result;
}

export function createGrowthStore(
  databaseUrl: string,
  contactHashingSecret: string,
) {
  const sql = getLifeMateSql(databaseUrl);
  const privateReferenceHash = createHmac(contactHashingSecret);

  async function createGift(input: {
    appUserId: string;
    body: Record<string, unknown>;
    idempotencyKey: string;
  }): Promise<Record<string, unknown>> {
    const payload = parseGiftPayload(input.body);
    const recipientPhoneHash = await hashContactPoint(
      contactHashingSecret,
      "Phone",
      payload.recipientPhone,
    );
    const requestHash = await sha256(JSON.stringify({
      recipientPhoneHash,
      targetKind: payload.targetKind,
      targetId: payload.targetId,
    }));
    const rows = await sql`
      select growth.create_gift_intent(
        ${input.appUserId}::uuid,
        ${recipientPhoneHash}::varchar,
        ${payload.targetKind}::varchar,
        ${payload.targetId}::uuid,
        ${input.idempotencyKey}::varchar,
        ${requestHash}::varchar
      ) as result
    `;
    const result = requireSuccessful(rows[0]?.result ?? {}, "gift_unavailable");
    return {
      giftIntentId: String(result.giftIntentId),
      status: String(result.status),
      expiresAtUtc: String(result.expiresAtUtc),
      replayed: Boolean(result.replayed),
    };
  }

  async function ensureReferralCode(
    appUserId: string,
  ): Promise<Record<string, unknown>> {
    const rows = await sql`
      select growth.ensure_referral_code(${appUserId}::uuid) as result
    `;
    const result = requireSuccessful(
      rows[0]?.result ?? {},
      "referral_code_unavailable",
    );
    return {
      referralCodeId: String(result.referralCodeId),
      code: String(result.codeValue),
      created: Boolean(result.created),
    };
  }

  async function attributeReferral(input: {
    appUserId: string;
    body: Record<string, unknown>;
    idempotencyKey: string;
  }): Promise<Record<string, unknown>> {
    const code = parseReferralPayload(input.body);
    const requestHash = await sha256(JSON.stringify({ code }));
    const rows = await sql`
      select growth.attribute_referral(
        ${input.appUserId}::uuid,
        ${code}::varchar,
        ${input.idempotencyKey}::varchar,
        ${requestHash}::varchar
      ) as result
    `;
    const result = requireSuccessful(
      rows[0]?.result ?? {},
      "referral_attribution_unavailable",
    );
    return {
      attributionId: String(result.attributionId),
      status: String(result.status),
      replayed: Boolean(result.replayed),
    };
  }

  async function submitAdvocacy(input: {
    appUserId: string;
    body: Record<string, unknown>;
    idempotencyKey: string;
  }): Promise<Record<string, unknown>> {
    const payload = parseAdvocacyPayload(input.body);
    const evidenceReferenceHash = await privateReferenceHash(
      `advocacy-evidence:v1|${payload.platformCode}|${payload.evidenceReference}`,
    );
    const requestHash = await sha256(JSON.stringify({
      platformCode: payload.platformCode,
      evidenceType: payload.evidenceType,
      evidenceReferenceHash,
    }));
    const rows = await sql`
      select growth.submit_advocacy(
        ${input.appUserId}::uuid,
        ${payload.platformCode}::varchar,
        ${payload.evidenceType}::varchar,
        ${evidenceReferenceHash}::varchar,
        ${input.idempotencyKey}::varchar,
        ${requestHash}::varchar
      ) as result
    `;
    const result = requireSuccessful(
      rows[0]?.result ?? {},
      "advocacy_submission_unavailable",
    );
    return {
      submissionId: String(result.submissionId),
      status: String(result.status),
      replayed: Boolean(result.replayed),
    };
  }

  async function listRewards(
    appUserId: string,
  ): Promise<Record<string, unknown>[]> {
    const rows = await sql`
      select * from growth.list_reward_events_for_app_user(${appUserId}::uuid)
    `;
    return rows.map((row: Row) => ({
      id: String(row.id),
      sourceKind: String(row.source_kind),
      rewardKind: String(row.reward_kind),
      status: String(row.status),
      createdAtUtc: String(row.created_at_utc),
      issuedAtUtc: row.issued_at_utc == null ? null : String(row.issued_at_utc),
    }));
  }

  return {
    createGift,
    ensureReferralCode,
    attributeReferral,
    submitAdvocacy,
    listRewards,
    hashEvidenceReference: privateReferenceHash,
  };
}

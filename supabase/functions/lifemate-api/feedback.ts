import { getLifeMateSql } from "./database_client.ts";
import { ApiError } from "./validation.ts";
type Row = Record<string, unknown>;
const kinds = new Set([
  "Feedback",
  "Nps",
  "BugReport",
  "FeatureRequest",
  "Advocacy",
]);
const productCode = /^[a-z][a-z0-9_-]{1,39}$/;
const appVersion = /^[A-Za-z0-9][A-Za-z0-9._+-]{0,79}$/;
const buildNumber = /^[A-Za-z0-9][A-Za-z0-9._+-]{0,39}$/;
export type FeedbackSubmission = {
  kind: "Feedback" | "Nps" | "BugReport" | "FeatureRequest" | "Advocacy";
  productCode: string;
  appVersion: string | null;
  buildNumber: string | null;
  npsScore: number | null;
  message: string | null;
  advocacyOptIn: boolean;
};
export function parseFeedbackSubmission(
  body: Record<string, unknown>,
): FeedbackSubmission {
  const allowed = new Set([
    "kind",
    "productCode",
    "appVersion",
    "buildNumber",
    "npsScore",
    "message",
    "advocacyOptIn",
  ]);
  for (const key of Object.keys(body)) {
    if (!allowed.has(key)) {
      throw new ApiError(
        400,
        "feedback_field_forbidden",
        "Feedback payload contains an unsupported field.",
      );
    }
  }
  const kind = String(body.kind ?? "").trim();
  if (!kinds.has(kind)) invalid("feedback_kind_invalid", "kind");
  const product = String(body.productCode ?? "").trim().toLowerCase();
  if (!productCode.test(product)) {
    invalid("feedback_product_invalid", "productCode");
  }
  const version = optionalText(body.appVersion, 80);
  if (version != null && !appVersion.test(version)) {
    invalid("feedback_app_version_invalid", "appVersion");
  }
  const build = optionalText(body.buildNumber, 40);
  if (build != null && !buildNumber.test(build)) {
    invalid("feedback_build_invalid", "buildNumber");
  }
  const message = optionalText(body.message, 2000);
  if (kind !== "Nps" && message == null) {
    invalid("feedback_message_required", "message");
  }
  const advocacyOptIn = body.advocacyOptIn === true;
  if (body.advocacyOptIn != null && typeof body.advocacyOptIn !== "boolean") {
    invalid("feedback_advocacy_opt_in_invalid", "advocacyOptIn");
  }
  let npsScore: number | null = null;
  if (kind === "Nps") {
    if (
      !Number.isInteger(body.npsScore) || Number(body.npsScore) < 0 ||
      Number(body.npsScore) > 10
    ) invalid("feedback_nps_score_invalid", "npsScore");
    npsScore = Number(body.npsScore);
  } else if (body.npsScore != null) {
    invalid("feedback_nps_score_forbidden", "npsScore");
  }
  if (kind === "Advocacy" && !advocacyOptIn) {
    throw new ApiError(
      400,
      "feedback_advocacy_opt_in_required",
      "Advocacy submissions require explicit opt-in.",
    );
  }
  if (kind !== "Advocacy" && advocacyOptIn) {
    throw new ApiError(
      400,
      "feedback_advocacy_opt_in_forbidden",
      "Advocacy opt-in is accepted only for Advocacy submissions.",
    );
  }
  return {
    kind: kind as FeedbackSubmission["kind"],
    productCode: product,
    appVersion: version,
    buildNumber: build,
    npsScore,
    message,
    advocacyOptIn,
  };
}
export function createFeedbackStore(databaseUrl: string) {
  const sql = getLifeMateSql(databaseUrl);
  return {
    async submit(
      appUserId: string,
      input: FeedbackSubmission,
      idempotencyKey: string,
    ): Promise<Row> {
      const rows =
        await sql`select feedback.submit_item(${appUserId}::uuid,${input.kind}::feedback.item_kind,${input.productCode},${input.appVersion},${input.buildNumber},${input.npsScore}::smallint,${input.message},${input.advocacyOptIn},${idempotencyKey}) as result`;
      const result = rows[0]?.result;
      if (!result || typeof result !== "object" || Array.isArray(result)) {
        throw new ApiError(
          503,
          "feedback_submission_unavailable",
          "Feedback could not be submitted.",
        );
      }
      return result as Row;
    },
  };
}
function optionalText(value: unknown, max: number): string | null {
  if (value == null) return null;
  if (typeof value !== "string") invalid("feedback_text_invalid", "text");
  const text = value.trim();
  if (text.length === 0 || text.length > max) {
    invalid("feedback_text_invalid", "text");
  }
  return text;
}
function invalid(code: string, field: string): never {
  throw new ApiError(400, code, `${field} is invalid.`);
}

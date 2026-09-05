import { getLifeMateSql } from "./database_client.ts";
import { ApiError } from "./validation.ts";

type Row = Record<string, unknown>;

const products = new Set(["wellmate", "caremate"]);
const platforms = new Set([
  "android",
  "ios",
  "web",
  "windows",
  "macos",
  "linux",
  "unknown",
]);
const mobilePolicyPlatforms = new Set([
  "android",
  "ios",
  "web",
  "windows",
  "macos",
  "linux",
]);
const safeVersion = /^[A-Za-z0-9][A-Za-z0-9._+-]{0,79}$/;
const safeBuild = /^[A-Za-z0-9][A-Za-z0-9._+-]{0,39}$/;
const safeCohort = /^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$/;

export type ProductVersionPresenceInput = {
  product: string;
  platform: string;
  appVersion: string;
  buildNumber: string;
  rolloutCohort: string | null;
};

export function parseProductVersionPresence(
  body: Record<string, unknown>,
): ProductVersionPresenceInput {
  const allowed = new Set([
    "product",
    "platform",
    "appVersion",
    "buildNumber",
    "rolloutCohort",
  ]);
  for (const key of Object.keys(body)) {
    if (!allowed.has(key)) {
      throw new ApiError(
        400,
        "product_version_field_forbidden",
        "Product version payload contains an unsupported field.",
      );
    }
  }

  const product = String(body.product ?? "").trim().toLowerCase();
  const platform = String(body.platform ?? "").trim().toLowerCase();
  const appVersion = String(body.appVersion ?? "").trim();
  const buildNumber = String(body.buildNumber ?? "unknown").trim();
  const rolloutCohort = body.rolloutCohort == null
    ? null
    : String(body.rolloutCohort).trim();

  if (!products.has(product)) invalid("product_invalid", "product");
  if (!platforms.has(platform)) invalid("platform_invalid", "platform");
  if (!safeVersion.test(appVersion)) {
    invalid("app_version_invalid", "appVersion");
  }
  if (!safeBuild.test(buildNumber)) {
    invalid("build_number_invalid", "buildNumber");
  }
  if (rolloutCohort != null && !safeCohort.test(rolloutCohort)) {
    invalid("rollout_cohort_invalid", "rolloutCohort");
  }

  return { product, platform, appVersion, buildNumber, rolloutCohort };
}

export function parseUpdatePolicyQuery(url: URL): {
  product: string;
  platform: string;
  currentVersion: string;
} {
  const product = (url.searchParams.get("product") ?? "").trim().toLowerCase();
  const platform = (url.searchParams.get("platform") ?? "").trim()
    .toLowerCase();
  const currentVersion = (url.searchParams.get("currentVersion") ?? "").trim();
  if (!products.has(product)) invalid("product_invalid", "product");
  if (!mobilePolicyPlatforms.has(platform)) {
    invalid("platform_invalid", "platform");
  }
  if (
    !safeVersion.test(currentVersion) || parseSemver(currentVersion) == null
  ) {
    invalid("app_version_invalid", "currentVersion");
  }
  return { product, platform, currentVersion };
}

export function createProductTelemetryV2Store(databaseUrl: string) {
  const sql = getLifeMateSql(databaseUrl);

  async function recordPresence(
    appUserId: string,
    input: ProductVersionPresenceInput,
  ): Promise<Row> {
    const rows = await sql`
      select analytics.record_product_version_presence(
        ${appUserId}::uuid,
        ${input.product},
        ${input.platform},
        ${input.appVersion},
        ${input.buildNumber},
        ${input.rolloutCohort}
      ) as result
    `;
    const result = rows[0]?.result;
    if (!result || typeof result !== "object" || Array.isArray(result)) {
      throw new ApiError(
        503,
        "product_version_record_unavailable",
        "Product version presence could not be recorded.",
      );
    }
    return result as Row;
  }

  async function updatePolicy(
    product: string,
    platform: string,
    currentVersion: string,
  ): Promise<Row> {
    const rows = await sql`
      select platform.current_product_update_policy(
        ${product},
        ${platform}
      ) as result
    `;
    const raw = rows[0]?.result;
    if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
      throw new ApiError(
        503,
        "update_policy_unavailable",
        "Update policy is temporarily unavailable.",
      );
    }
    return evaluateUpdatePolicy(raw as Row, currentVersion);
  }

  return { recordPresence, updatePolicy };
}

export function evaluateUpdatePolicy(
  policy: Row,
  currentVersion: string,
): Row {
  const minimum = textOrNull(policy.minimumSupportedVersion);
  const recommended = textOrNull(policy.recommendedVersion);
  const mode = String(policy.mode ?? "Soft");
  const reasonCode = String(policy.reasonCode ?? "Routine");

  const belowMinimum = minimum == null
    ? false
    : compareSemver(currentVersion, minimum) < 0;
  const belowRecommended = recommended == null
    ? false
    : compareSemver(currentVersion, recommended) < 0;
  const force = belowMinimum && mode === "Force" &&
    ["Critical", "Security", "BreakingCompatibility"].includes(reasonCode);
  const soft = !force && (belowMinimum || belowRecommended);

  return {
    ...policy,
    currentVersion,
    updateState: force ? "force" : soft ? "soft" : "current",
    forceUpdate: force,
    softUpdate: soft,
  };
}

export function compareSemver(left: string, right: string): number {
  const a = parseSemver(left);
  const b = parseSemver(right);
  if (!a || !b) {
    throw new ApiError(
      400,
      "app_version_invalid",
      "Version must use semantic version format.",
    );
  }
  for (let index = 0; index < 3; index += 1) {
    if (a.core[index] !== b.core[index]) {
      return a.core[index] < b.core[index] ? -1 : 1;
    }
  }
  if (a.pre.length === 0 && b.pre.length === 0) return 0;
  if (a.pre.length === 0) return 1;
  if (b.pre.length === 0) return -1;
  const length = Math.max(a.pre.length, b.pre.length);
  for (let index = 0; index < length; index += 1) {
    const av = a.pre[index];
    const bv = b.pre[index];
    if (av == null) return -1;
    if (bv == null) return 1;
    if (av === bv) continue;
    const an = /^\d+$/.test(av) ? Number(av) : null;
    const bn = /^\d+$/.test(bv) ? Number(bv) : null;
    if (an != null && bn != null) return an < bn ? -1 : 1;
    if (an != null) return -1;
    if (bn != null) return 1;
    return av < bv ? -1 : 1;
  }
  return 0;
}

function parseSemver(
  value: string,
): { core: [number, number, number]; pre: string[] } | null {
  const match = value.match(
    /^(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.-]+))?(?:\+[0-9A-Za-z.-]+)?$/,
  );
  if (!match) return null;
  return {
    core: [Number(match[1]), Number(match[2]), Number(match[3])],
    pre: match[4]?.split(".") ?? [],
  };
}

function textOrNull(value: unknown): string | null {
  const text = value == null ? "" : String(value).trim();
  return text.length === 0 ? null : text;
}

function invalid(code: string, field: string): never {
  throw new ApiError(400, code, `${field} is invalid.`);
}

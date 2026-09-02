import { getLifeMateSql } from "./database_client.ts";
import { createProductTelemetryV2Store } from "./product_telemetry_v2.ts";
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
]);
const semver = /^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$/;

const protectedClientFlags = [
  "client.women_calendar.enabled",
  "client.care_pairing.enabled",
] as const;

// These SQLSTATEs mean the remote-config control plane is temporarily not
// usable by this deployed API version. They are intentionally narrow: auth,
// identity/account mapping, validation and arbitrary application errors are
// not swallowed by the fail-closed path.
const failClosedControlPlaneSqlStates = new Set([
  "3F000", // invalid_schema_name
  "42P01", // undefined_table
  "42703", // undefined_column
  "42883", // undefined_function
  "42501", // insufficient_privilege
]);

export function parseClientRuntimeConfigQuery(url: URL) {
  const product = (url.searchParams.get("product") ?? "").trim().toLowerCase();
  const platform = (url.searchParams.get("platform") ?? "").trim().toLowerCase();
  const currentVersion = (url.searchParams.get("currentVersion") ?? "").trim();
  const betaRaw = (url.searchParams.get("beta") ?? "false").trim().toLowerCase();
  if (!products.has(product)) invalid("product_invalid", "product");
  if (!platforms.has(platform)) invalid("platform_invalid", "platform");
  if (!semver.test(currentVersion)) invalid("app_version_invalid", "currentVersion");
  if (betaRaw !== "true" && betaRaw !== "false") invalid("beta_invalid", "beta");
  return {
    product,
    platform,
    currentVersion,
    beta: betaRaw === "true",
  };
}

export function createClientRemoteConfigStore(databaseUrl: string) {
  const sql = getLifeMateSql(databaseUrl);
  const telemetry = createProductTelemetryV2Store(databaseUrl);

  async function snapshot(input: {
    appUserId: string;
    product: string;
    platform: string;
    currentVersion: string;
    beta: boolean;
  }): Promise<Row> {
    try {
      const rows = await sql`
        select platform.client_control_evaluations(
          ${input.appUserId}::uuid,
          ${input.product},
          ${input.beta}
        ) as result
      `;
      const controls = withProtectedFailClosedDefaults(
        Array.isArray(rows[0]?.result) ? rows[0].result as unknown[] : [],
      );
      const updatePolicy = await telemetry.updatePolicy(
        input.product,
        input.platform,
        input.currentVersion,
      );
      const definitionVersion = controls.reduce(
        (max, item) => {
          if (!item || typeof item !== "object" || Array.isArray(item)) return max;
          const value = Number((item as Row).definitionVersion ?? 0);
          return Number.isInteger(value) && value > max ? value : max;
        },
        0,
      );
      return {
        product: input.product,
        platform: input.platform,
        controls,
        updatePolicy,
        snapshotVersion: `controls-${definitionVersion}:update-${Number(updatePolicy.policyVersion ?? 0)}`,
        authoritative: "server",
        cacheTtlSeconds: 60,
        fetchedAtUtc: new Date().toISOString(),
      };
    } catch (error) {
      if (!isFailClosedControlPlaneError(error)) throw error;
      console.warn(
        `Client runtime config control plane unavailable (${sqlState(error) ?? "unknown"}); serving fail-closed defaults.`,
      );
      return failClosedClientRuntimeConfig(input);
    }
  }

  return { snapshot };
}

export function withProtectedFailClosedDefaults(
  controls: unknown[],
): unknown[] {
  const result = [...controls];
  const present = new Set(
    controls
      .filter((item): item is Row =>
        item != null && typeof item === "object" && !Array.isArray(item)
      )
      .map((item) => String(item.key ?? "")),
  );
  for (const key of protectedClientFlags) {
    if (present.has(key)) continue;
    result.push(failClosedControl(key, "missing_control"));
  }
  return result;
}

export function isFailClosedControlPlaneError(error: unknown): boolean {
  const code = sqlState(error);
  return code != null && failClosedControlPlaneSqlStates.has(code);
}

export function failClosedClientRuntimeConfig(input: {
  product: string;
  platform: string;
  currentVersion: string;
}): Row {
  return {
    product: input.product,
    platform: input.platform,
    controls: protectedClientFlags.map((key) =>
      failClosedControl(key, "server_fail_closed")
    ),
    updatePolicy: {
      currentVersion: input.currentVersion,
      updateState: "current",
      forceUpdate: false,
      softUpdate: false,
      minimumSupportedVersion: null,
      recommendedVersion: null,
      mode: "Soft",
      reasonCode: "Unavailable",
      messageKey: null,
      policyVersion: 0,
    },
    snapshotVersion: "controls-0:update-0:fail-closed",
    authoritative: "server_fail_closed",
    cacheTtlSeconds: 15,
    fetchedAtUtc: new Date().toISOString(),
  };
}

function failClosedControl(key: string, source: string): Row {
  return {
    key,
    kind: "FeatureFlag",
    valueType: "Boolean",
    value: false,
    definitionVersion: 0,
    source,
    ruleVersion: null,
    failClosed: true,
  };
}

function sqlState(error: unknown): string | null {
  if (!error || typeof error !== "object") return null;
  const value = (error as { code?: unknown }).code;
  return typeof value === "string" && value.length > 0 ? value : null;
}

function invalid(code: string, field: string): never {
  throw new ApiError(400, code, `${field} is invalid.`);
}

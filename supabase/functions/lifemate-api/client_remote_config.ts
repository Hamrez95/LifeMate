import { getLifeMateSql } from "./database_client.ts";
import { createProductTelemetryV2Store } from "./product_telemetry_v2.ts";
import { ApiError } from "./validation.ts";

type Row = Record<string, unknown>;

const products = new Set(["wellmate", "caremate", "cocoonmate"]);
const platforms = new Set([
  "android",
  "ios",
  "web",
  "windows",
  "macos",
  "linux",
]);
const semver = /^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$/;

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
    const rows = await sql`
      select platform.client_control_evaluations(
        ${input.appUserId}::uuid,
        ${input.product},
        ${input.beta}
      ) as result
    `;
    const controls = Array.isArray(rows[0]?.result)
      ? rows[0].result as unknown[]
      : [];
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
  }

  return { snapshot };
}

function invalid(code: string, field: string): never {
  throw new ApiError(400, code, `${field} is invalid.`);
}

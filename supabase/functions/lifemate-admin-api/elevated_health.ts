import { ApiError, requireUuid } from "./validation.ts";

export type ElevatedHealthCapability =
  | "health.read.elevated"
  | "women_health.read.elevated";

export type ElevatedHealthQuery = {
  subjectPersonId: string;
  capability: ElevatedHealthCapability;
  limit: number;
};

const PATH = /^\/api\/v1\/security\/elevated-health\/([^/]+)$/i;

export function parseElevatedHealthQuery(url: URL): ElevatedHealthQuery | null {
  const match = PATH.exec(url.pathname);
  if (!match) return null;
  const capability = url.searchParams.get("capability");
  if (
    capability !== "health.read.elevated" &&
    capability !== "women_health.read.elevated"
  ) {
    throw new ApiError(
      400,
      "elevated_capability_invalid",
      "An exact elevated health capability is required.",
    );
  }
  const rawLimit = url.searchParams.get("limit") ?? "50";
  if (!/^\d+$/.test(rawLimit)) {
    throw new ApiError(400, "elevated_limit_invalid", "Limit is invalid.");
  }
  const limit = Number(rawLimit);
  if (limit < 1 || limit > 50) {
    throw new ApiError(
      400,
      "elevated_limit_invalid",
      "Limit must be between 1 and 50.",
    );
  }
  return {
    subjectPersonId: requireUuid(match[1], "subjectPersonId"),
    capability,
    limit,
  };
}

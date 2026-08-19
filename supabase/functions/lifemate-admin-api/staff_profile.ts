import { ApiError } from "./validation.ts";

export type StaffProfileInput = {
  username: string;
  displayName: string;
};

const USERNAME = /^[a-z0-9][a-z0-9._-]{2,31}$/;

export async function parseStaffProfilePayload(
  request: Request,
): Promise<StaffProfileInput> {
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    throw new ApiError(400, "staff_profile_invalid", "Staff profile payload is invalid.");
  }

  if (!body || typeof body !== "object" || Array.isArray(body)) {
    throw new ApiError(400, "staff_profile_invalid", "Staff profile payload is invalid.");
  }

  const record = body as Record<string, unknown>;
  const username = typeof record.username === "string"
    ? record.username.trim().toLowerCase()
    : "";
  const displayName = typeof record.displayName === "string"
    ? record.displayName.trim().replace(/\s+/g, " ")
    : "";

  if (!USERNAME.test(username) || displayName.length < 2 || displayName.length > 120) {
    throw new ApiError(400, "staff_profile_invalid", "Staff profile payload is invalid.");
  }

  return { username, displayName };
}

export async function hashStaffProfileRequest(
  input: StaffProfileInput,
): Promise<string> {
  const bytes = new TextEncoder().encode(JSON.stringify(input));
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest))
    .map((value) => value.toString(16).padStart(2, "0"))
    .join("");
}

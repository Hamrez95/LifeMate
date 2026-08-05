from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def write(path: str, value: str) -> None:
    target = ROOT / path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(value, encoding="utf-8")


def replace_once(path: str, old: str, new: str) -> None:
    value = read(path)
    if new in value:
        return
    if old not in value:
        raise RuntimeError(f"Expected marker not found in {path}: {old[:140]!r}")
    write(path, value.replace(old, new, 1))


# Additive schema: only an opaque private object path is persisted.
write(
    "supabase/migrations/20260805023000_add_profile_photo_path.sql",
    """begin;

alter table lifemate.user_profiles
  add column if not exists profile_photo_path character varying(512);

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'ck_user_profiles_profile_photo_path'
      and conrelid = 'lifemate.user_profiles'::regclass
  ) then
    alter table lifemate.user_profiles
      add constraint ck_user_profiles_profile_photo_path check (
        profile_photo_path is null
        or profile_photo_path ~
          '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\\.(jpg|png|webp)$'
      );
  end if;
end $$;

commit;
""",
)

# Private Supabase Storage adapter. The service credential never leaves Edge.
write(
    "supabase/functions/lifemate-api/profile_photo.ts",
    """import { ApiError } from "./validation.ts";

export const profilePhotoBucket = "profile-photos";
export const profilePhotoMaximumBytes = 3 * 1024 * 1024;
const signedUrlLifetimeSeconds = 15 * 60;

export type ValidatedProfilePhoto = {
  contentType: "image/jpeg" | "image/png" | "image/webp";
  extension: "jpg" | "png" | "webp";
};

export function validateProfilePhoto(
  bytes: Uint8Array,
  rawContentType: string,
): ValidatedProfilePhoto {
  if (bytes.length == 0 || bytes.length > profilePhotoMaximumBytes) {
    throw new ApiError(
      413,
      "profile_photo_too_large",
      "Profile photo must be between 1 byte and 3 MB.",
    );
  }

  const contentType = rawContentType.split(";", 1)[0].trim().toLowerCase();
  const jpeg = bytes.length >= 3 &&
    bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff;
  const png = bytes.length >= 8 &&
    bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4e &&
    bytes[3] === 0x47 && bytes[4] === 0x0d && bytes[5] === 0x0a &&
    bytes[6] === 0x1a && bytes[7] === 0x0a;
  const webp = bytes.length >= 12 &&
    bytes[0] === 0x52 && bytes[1] === 0x49 && bytes[2] === 0x46 &&
    bytes[3] === 0x46 && bytes[8] === 0x57 && bytes[9] === 0x45 &&
    bytes[10] === 0x42 && bytes[11] === 0x50;

  if (contentType === "image/jpeg" && jpeg) {
    return { contentType: "image/jpeg", extension: "jpg" };
  }
  if (contentType === "image/png" && png) {
    return { contentType: "image/png", extension: "png" };
  }
  if (contentType === "image/webp" && webp) {
    return { contentType: "image/webp", extension: "webp" };
  }

  throw new ApiError(
    415,
    "invalid_profile_photo",
    "Only genuine JPEG, PNG, or WebP profile photos are supported.",
  );
}

export function createProfilePhotoStorage(
  supabaseUrl: string,
  serviceRoleKey: string,
) {
  const storageRoot = `${supabaseUrl.replace(/\\/+$/, "")}/storage/v1`;
  let bucketPromise: Promise<void> | null = null;

  const headers = (contentType?: string): HeadersInit => ({
    apikey: serviceRoleKey,
    authorization: `Bearer ${serviceRoleKey}`,
    ...(contentType == null ? {} : { "content-type": contentType }),
  });

  async function ensurePrivateBucket(): Promise<void> {
    bucketPromise ??= (async () => {
      const existing = await fetch(`${storageRoot}/bucket/${profilePhotoBucket}`, {
        method: "GET",
        headers: headers(),
      });
      if (existing.ok) return;
      if (existing.status !== 404) {
        throw storageUnavailable();
      }

      const created = await fetch(`${storageRoot}/bucket`, {
        method: "POST",
        headers: headers("application/json"),
        body: JSON.stringify({
          id: profilePhotoBucket,
          name: profilePhotoBucket,
          public: false,
          file_size_limit: profilePhotoMaximumBytes,
          allowed_mime_types: ["image/jpeg", "image/png", "image/webp"],
        }),
      });
      // 409 is a harmless race with another cold start creating the same bucket.
      if (!created.ok && created.status !== 409) {
        throw storageUnavailable();
      }
    })().catch((error) => {
      bucketPromise = null;
      throw error;
    });
    await bucketPromise;
  }

  async function upload(
    userId: string,
    bytes: Uint8Array,
    rawContentType: string,
  ): Promise<string> {
    const validated = validateProfilePhoto(bytes, rawContentType);
    await ensurePrivateBucket();
    const objectPath = `${userId}/${crypto.randomUUID()}.${validated.extension}`;
    const response = await fetch(objectUrl(objectPath), {
      method: "POST",
      headers: {
        ...headers(validated.contentType),
        "x-upsert": "false",
        "cache-control": "3600",
      },
      body: bytes,
    });
    if (!response.ok) throw storageUnavailable();
    return objectPath;
  }

  async function createSignedUrl(objectPath: string): Promise<string> {
    assertSafePath(objectPath);
    await ensurePrivateBucket();
    const response = await fetch(
      `${storageRoot}/object/sign/${profilePhotoBucket}/${encodePath(objectPath)}`,
      {
        method: "POST",
        headers: headers("application/json"),
        body: JSON.stringify({ expiresIn: signedUrlLifetimeSeconds }),
      },
    );
    if (!response.ok) throw storageUnavailable();
    const payload = await response.json() as Record<string, unknown>;
    const signed = payload.signedURL ?? payload.signedUrl;
    if (typeof signed !== "string" || signed.length == 0) {
      throw storageUnavailable();
    }
    return signed.startsWith("http")
      ? signed
      : `${supabaseUrl.replace(/\\/+$/, "")}${signed.startsWith("/") ? "" : "/"}${signed}`;
  }

  async function remove(objectPath: string): Promise<void> {
    assertSafePath(objectPath);
    await ensurePrivateBucket();
    const response = await fetch(
      `${storageRoot}/object/${profilePhotoBucket}`,
      {
        method: "DELETE",
        headers: headers("application/json"),
        body: JSON.stringify({ prefixes: [objectPath] }),
      },
    );
    if (!response.ok && response.status !== 404) throw storageUnavailable();
  }

  function objectUrl(objectPath: string): string {
    assertSafePath(objectPath);
    return `${storageRoot}/object/${profilePhotoBucket}/${encodePath(objectPath)}`;
  }

  return { upload, createSignedUrl, remove };
}

function encodePath(value: string): string {
  return value.split("/").map(encodeURIComponent).join("/");
}

function assertSafePath(value: string): void {
  if (
    !/^[0-9a-f-]{36}\\/[0-9a-f-]{36}\\.(jpg|png|webp)$/i.test(value) ||
    value.includes("..")
  ) {
    throw new ApiError(
      400,
      "invalid_profile_photo_path",
      "Profile photo path is invalid.",
    );
  }
}

function storageUnavailable(): ApiError {
  return new ApiError(
    503,
    "profile_photo_storage_unavailable",
    "Profile photo storage is temporarily unavailable.",
  );
}
""",
)

write(
    "supabase/functions/lifemate-api/profile_photo_test.ts",
    """import { assertEquals, assertThrows } from "jsr:@std/assert@1.0.14";
import { ApiError } from "./validation.ts";
import {
  profilePhotoMaximumBytes,
  validateProfilePhoto,
} from "./profile_photo.ts";

Deno.test("profile photo validation accepts matching JPEG PNG and WebP signatures", () => {
  assertEquals(
    validateProfilePhoto(new Uint8Array([0xff, 0xd8, 0xff, 0x00]), "image/jpeg"),
    { contentType: "image/jpeg", extension: "jpg" },
  );
  assertEquals(
    validateProfilePhoto(
      new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
      "image/png; charset=binary",
    ),
    { contentType: "image/png", extension: "png" },
  );
  assertEquals(
    validateProfilePhoto(
      new Uint8Array([
        0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0,
        0x57, 0x45, 0x42, 0x50,
      ]),
      "image/webp",
    ),
    { contentType: "image/webp", extension: "webp" },
  );
});

Deno.test("profile photo validation rejects spoofed and oversized payloads", () => {
  assertThrows(
    () => validateProfilePhoto(new Uint8Array([1, 2, 3]), "image/jpeg"),
    ApiError,
  );
  assertThrows(
    () => validateProfilePhoto(
      new Uint8Array(profilePhotoMaximumBytes + 1),
      "image/png",
    ),
    ApiError,
  );
});
""",
)

# Runtime configuration keeps the service credential server-only.
replace_once(
    "supabase/functions/lifemate-api/runtime_config.ts",
    """  publishableKey: string;
  contactHashingSecret: string;""",
    """  publishableKey: string;
  storageServiceKey: string;
  contactHashingSecret: string;""",
)
replace_once(
    "supabase/functions/lifemate-api/runtime_config.ts",
    """  if (!databaseUrl || !supabaseUrl || !publishableKey) {
    throw new Error("Required Supabase runtime configuration is missing.");
  }""",
    """  if (!databaseUrl || !supabaseUrl || !publishableKey || !serviceRole) {
    throw new Error("Required Supabase runtime configuration is missing.");
  }""",
)
replace_once(
    "supabase/functions/lifemate-api/runtime_config.ts",
    """    supabaseUrl,
    publishableKey,
    contactHashingSecret,""",
    """    supabaseUrl,
    publishableKey,
    storageServiceKey: serviceRole,
    contactHashingSecret,""",
)

# Profile persistence detects the additive column and keeps existing profile reads
# compatible until the candidate migration is applied.
path = "supabase/functions/lifemate-api/profile.ts"
value = read(path)
if "getProfilePhotoPath" not in value:
    value = value.replace(
        "  let versionColumnPromise: Promise<boolean> | null = null;\n",
        "  let versionColumnPromise: Promise<boolean> | null = null;\n  let photoColumnPromise: Promise<boolean> | null = null;\n",
        1,
    )
    marker = """  async function getProfile(userId: string): Promise<Record<string, unknown>> {"""
    helper = """  function hasPhotoColumn(): Promise<boolean> {
    photoColumnPromise ??= sql`
      select exists (
        select 1
        from information_schema.columns
        where table_schema = 'lifemate'
          and table_name = 'user_profiles'
          and column_name = 'profile_photo_path'
      ) as present
    `.then((rows: Row[]) => rows[0]?.present === true);
    return photoColumnPromise;
  }

  async function getProfilePhotoPath(userId: string): Promise<string | null> {
    if (!(await hasPhotoColumn())) return null;
    const rows = await sql`
      select profile_photo_path
      from lifemate.user_profiles
      where user_id = ${userId}
      limit 1
    `;
    if (!rows[0]) {
      throw new ApiError(404, "profile_missing", "User profile was not found.");
    }
    const value = rows[0].profile_photo_path;
    return typeof value === "string" && value.length > 0 ? value : null;
  }

  async function replaceProfilePhotoPath(
    userId: string,
    nextPath: string | null,
  ): Promise<string | null> {
    if (!(await hasPhotoColumn())) {
      throw new ApiError(
        503,
        "profile_photo_not_ready",
        "Profile photo storage is not ready for this environment.",
      );
    }
    if (nextPath != null && !nextPath.startsWith(`${userId}/`)) {
      throw new ApiError(
        400,
        "invalid_profile_photo_path",
        "Profile photo path does not belong to the current user.",
      );
    }
    const usesVersionColumn = await hasVersionColumn();
    return await sql.begin(async (tx: any) => {
      const current = await tx`
        select id, profile_photo_path
        from lifemate.user_profiles
        where user_id = ${userId}
        for update
      `;
      if (!current[0]) {
        throw new ApiError(404, "profile_missing", "User profile was not found.");
      }
      const previous = typeof current[0].profile_photo_path === "string"
        ? current[0].profile_photo_path
        : null;
      if (usesVersionColumn) {
        await tx`
          update lifemate.user_profiles
          set profile_photo_path = ${nextPath},
              version = version + 1,
              updated_at_utc = now()
          where user_id = ${userId}
        `;
      } else {
        await tx`
          update lifemate.user_profiles
          set profile_photo_path = ${nextPath},
              updated_at_utc = greatest(
                now(),
                updated_at_utc + interval '1 millisecond'
              )
          where user_id = ${userId}
        `;
      }
      await tx`
        insert into lifemate.audit_logs
          (id, actor_user_id, action, resource_type, resource_id,
           metadata_json, created_at_utc)
        values
          (${crypto.randomUUID()}, ${userId},
           ${nextPath == null ? "profile.photo_deleted" : "profile.photo_updated"},
           'user_profile', ${current[0].id}, null, now())
      `;
      return previous;
    });
  }

"""
    if marker not in value:
        raise RuntimeError("Profile get marker was not found")
    value = value.replace(marker, helper + marker, 1)
    value = value.replace(
        "  return { getProfile, updateProfile };\n",
        "  return {\n    getProfile,\n    updateProfile,\n    getProfilePhotoPath,\n    replaceProfilePhotoPath,\n  };\n",
        1,
    )
    write(path, value)

# Route upload/delete and hydrate private signed URLs into both /me and /profile.
path = "supabase/functions/lifemate-api/index.ts"
value = read(path)
if "createProfilePhotoStorage" not in value:
    value = value.replace(
        'import { createProfileStore } from "./profile.ts";\n',
        'import { createProfileStore } from "./profile.ts";\nimport {\n  createProfilePhotoStorage,\n  profilePhotoMaximumBytes,\n} from "./profile_photo.ts";\n',
        1,
    )
    value = value.replace(
        """  publishableKey,
  contactHashingSecret,""",
        """  publishableKey,
  storageServiceKey,
  contactHashingSecret,""",
        1,
    )
    value = value.replace(
        "const profiles = createProfileStore(databaseUrl);\n",
        "const profiles = createProfileStore(databaseUrl);\nconst profilePhotos = createProfilePhotoStorage(\n  supabaseUrl,\n  storageServiceKey,\n);\n",
        1,
    )
    value = value.replace(
        """  if (request.method === "GET" && path === "/api/v1/me") {
    return json(await db.currentUser(identity));
  }
  if (request.method === "GET" && path === "/api/v1/me/profile") {
    return json(await profiles.getProfile(identity.appUserId));
  }
  if (request.method === "PATCH" && path === "/api/v1/me/profile") {
    enforceRateLimit(`profile:${identity.appUserId}`, 20, 60 * 60_000);
    return json(
      await profiles.updateProfile(
        identity.appUserId,
        auth,
        await readJsonObject(request),
      ),
    );
  }""",
        """  if (request.method === "GET" && path === "/api/v1/me") {
    const current = await db.currentUser(identity);
    return json({
      ...current,
      profile: await presentProfile(identity.appUserId),
    });
  }
  if (request.method === "GET" && path === "/api/v1/me/profile") {
    return json(await presentProfile(identity.appUserId));
  }
  if (request.method === "PATCH" && path === "/api/v1/me/profile") {
    enforceRateLimit(`profile:${identity.appUserId}`, 20, 60 * 60_000);
    await profiles.updateProfile(
      identity.appUserId,
      auth,
      await readJsonObject(request),
    );
    return json(await presentProfile(identity.appUserId));
  }
  if (request.method === "PUT" && path === "/api/v1/me/profile/photo") {
    enforceRateLimit(`profile-photo:${identity.appUserId}`, 8, 60 * 60_000);
    const declaredLength = Number(request.headers.get("content-length") ?? 0);
    if (Number.isFinite(declaredLength) &&
      declaredLength > profilePhotoMaximumBytes) {
      throw new ApiError(
        413,
        "profile_photo_too_large",
        "Profile photo must be no larger than 3 MB.",
      );
    }
    const bytes = new Uint8Array(await request.arrayBuffer());
    const nextPath = await profilePhotos.upload(
      identity.appUserId,
      bytes,
      request.headers.get("content-type") ?? "",
    );
    let previousPath: string | null = null;
    try {
      previousPath = await profiles.replaceProfilePhotoPath(
        identity.appUserId,
        nextPath,
      );
    } catch (error) {
      await profilePhotos.remove(nextPath).catch(() => undefined);
      throw error;
    }
    if (previousPath != null && previousPath !== nextPath) {
      await profilePhotos.remove(previousPath).catch(() => {
        console.warn("Previous profile photo cleanup was deferred.");
      });
    }
    return json(await presentProfile(identity.appUserId));
  }
  if (request.method === "DELETE" && path === "/api/v1/me/profile/photo") {
    enforceRateLimit(`profile-photo:${identity.appUserId}`, 8, 60 * 60_000);
    const previousPath = await profiles.replaceProfilePhotoPath(
      identity.appUserId,
      null,
    );
    if (previousPath != null) {
      await profilePhotos.remove(previousPath).catch(() => {
        console.warn("Deleted profile photo cleanup was deferred.");
      });
    }
    return json(await presentProfile(identity.appUserId));
  }""",
        1,
    )
    # Insert presenter before the women-calendar guard near the bottom.
    marker = """function requireWomenCalendarPilot(): void {"""
    presenter = """async function presentProfile(
  userId: string,
): Promise<Record<string, unknown>> {
  const profile = await profiles.getProfile(userId);
  const objectPath = await profiles.getProfilePhotoPath(userId);
  let profilePhotoUrl: string | null = null;
  if (objectPath != null) {
    try {
      profilePhotoUrl = await profilePhotos.createSignedUrl(objectPath);
    } catch {
      // The avatar catalog remains a safe fallback during a transient storage
      // outage; profile reads must not be taken down by image delivery.
      profilePhotoUrl = null;
    }
  }
  return { ...profile, profilePhotoUrl };
}

"""
    if marker not in value:
        raise RuntimeError("Index presenter marker was not found")
    value = value.replace(marker, presenter + marker, 1)
    write(path, value)

# Deno checks/tests include the pure validation contract.
path = "supabase/functions/lifemate-api/deno.json"
value = read(path)
if "profile_photo_test.ts" not in value:
    value = value.replace(
        "profile_test.ts",
        "profile_test.ts profile_photo_test.ts",
    )
    write(path, value)

# Existing Edge workflows apply and assert the additive profile-photo schema.
for workflow in [
    ".github/workflows/edge-api.yml",
    ".github/workflows/women-calendar-pilot-audit.yml",
]:
    target = ROOT / workflow
    if not target.exists():
        continue
    value = read(workflow)
    migration = "supabase/migrations/20260805023000_add_profile_photo_path.sql"
    if migration not in value:
        marker = "supabase/migrations/20260805013000_add_reminder_lead_times.sql"
        if marker in value:
            value = value.replace(marker, marker + " \\\n            " + migration)
        else:
            marker = "supabase/migrations/20260804213000_add_profile_avatar_key.sql"
            if marker not in value:
                raise RuntimeError(f"Migration marker missing in {workflow}")
            value = value.replace(marker, marker + " \\\n            " + migration)
        write(workflow, value)

print("Secure profile-photo backend materialized.")

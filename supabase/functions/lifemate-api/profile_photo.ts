import { ApiError } from "./validation.ts";

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
  const storageRoot = `${supabaseUrl.replace(/\/+$/, "")}/storage/v1`;
  let bucketPromise: Promise<void> | null = null;

  const headers = (contentType?: string): Record<string, string> => ({
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
    const uploadBytes = new Uint8Array(bytes.length);
    uploadBytes.set(bytes);
    await ensurePrivateBucket();
    const objectPath = `${userId}/${crypto.randomUUID()}.${validated.extension}`;
    const response = await fetch(objectUrl(objectPath), {
      method: "POST",
      headers: {
        ...headers(validated.contentType),
        "x-upsert": "false",
        "cache-control": "3600",
      },
      body: uploadBytes.buffer,
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
    if (signed.startsWith("http")) return signed;
    if (signed.startsWith("/storage/v1/")) {
      return `${supabaseUrl.replace(/\/+$/, "")}${signed}`;
    }
    return `${storageRoot}${signed.startsWith("/") ? "" : "/"}${signed}`;
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
    !/^[0-9a-f-]{36}\/[0-9a-f-]{36}\.(jpg|png|webp)$/i.test(value) ||
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

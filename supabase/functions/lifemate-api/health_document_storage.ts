import { ApiError } from "./validation.ts";

/** Private object storage for the Person-owned Health Record. */
export const healthDocumentBucket = "health-records";
export const healthDocumentMaximumBytes = 15 * 1024 * 1024;
export const healthDocumentSignedUrlLifetimeSeconds = 10 * 60;

export type HealthDocumentKind = {
  contentType:
    | "image/jpeg"
    | "image/png"
    | "image/webp"
    | "image/heic"
    | "application/pdf";
  extension: "jpg" | "png" | "webp" | "heic" | "pdf";
};

/**
 * Validates both the declared MIME type and the file signature. The client may
 * compress images before upload, but the edge must still validate the final
 * bytes because browser-provided MIME types are not trusted.
 */
export function validateHealthDocument(
  bytes: Uint8Array,
  rawContentType: string,
): HealthDocumentKind {
  if (bytes.length < 1 || bytes.length > healthDocumentMaximumBytes) {
    throw new ApiError(
      413,
      "health_document_too_large",
      "Health document must be between 1 byte and 15 MB.",
    );
  }
  const type = rawContentType.split(";", 1)[0].trim().toLowerCase();
  const jpeg = bytes.length >= 3 && bytes[0] === 0xff && bytes[1] === 0xd8 &&
    bytes[2] === 0xff;
  const png = bytes.length >= 8 && bytes[0] === 0x89 && bytes[1] === 0x50 &&
    bytes[2] === 0x4e && bytes[3] === 0x47 && bytes[4] === 0x0d &&
    bytes[5] === 0x0a && bytes[6] === 0x1a && bytes[7] === 0x0a;
  const webp = bytes.length >= 12 && bytes[0] === 0x52 && bytes[1] === 0x49 &&
    bytes[2] === 0x46 && bytes[3] === 0x46 && bytes[8] === 0x57 &&
    bytes[9] === 0x45 && bytes[10] === 0x42 && bytes[11] === 0x50;
  const pdf = bytes.length >= 5 &&
    new TextDecoder().decode(bytes.slice(0, 5)) === "%PDF-";
  const heic = isHeic(bytes);

  if (type === "image/jpeg" && jpeg) {
    return { contentType: "image/jpeg", extension: "jpg" };
  }
  if (type === "image/png" && png) {
    return { contentType: "image/png", extension: "png" };
  }
  if (type === "image/webp" && webp) {
    return { contentType: "image/webp", extension: "webp" };
  }
  if (type === "image/heic" && heic) {
    return { contentType: "image/heic", extension: "heic" };
  }
  if (type === "application/pdf" && pdf) {
    return { contentType: "application/pdf", extension: "pdf" };
  }
  throw new ApiError(
    415,
    "health_document_invalid",
    "Document type or file signature is invalid.",
  );
}

export function createHealthDocumentStorage(
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
      const current = await fetch(`${storageRoot}/bucket/${healthDocumentBucket}`, {
        headers: headers(),
      });
      if (current.ok) return;
      if (current.status !== 400 && current.status !== 404) throw unavailable();
      const created = await fetch(`${storageRoot}/bucket`, {
        method: "POST",
        headers: headers("application/json"),
        body: JSON.stringify({
          id: healthDocumentBucket,
          name: healthDocumentBucket,
          public: false,
          file_size_limit: healthDocumentMaximumBytes,
          allowed_mime_types: [
            "image/jpeg",
            "image/png",
            "image/webp",
            "image/heic",
            "application/pdf",
          ],
        }),
      });
      if (!created.ok && created.status !== 409) throw unavailable();
    })().catch((error) => {
      bucketPromise = null;
      throw error;
    });
    await bucketPromise;
  }

  async function upload(
    ownerPersonId: string,
    documentId: string,
    bytes: Uint8Array,
    rawContentType: string,
  ) {
    const validated = validateHealthDocument(bytes, rawContentType);
    const objectKey = `${ownerPersonId}/${documentId}/${crypto.randomUUID()}.${validated.extension}`;
    assertSafeObjectKey(objectKey);
    await ensurePrivateBucket();
    const copy = new Uint8Array(bytes.length);
    copy.set(bytes);
    const response = await fetch(
      `${storageRoot}/object/${healthDocumentBucket}/${encodePath(objectKey)}`,
      {
        method: "POST",
        headers: {
          ...headers(validated.contentType),
          "x-upsert": "false",
          "cache-control": "no-store",
        },
        body: copy.buffer,
      },
    );
    if (!response.ok) throw unavailable();
    return { objectKey, ...validated };
  }

  async function signedDownload(objectKey: string): Promise<string> {
    assertSafeObjectKey(objectKey);
    await ensurePrivateBucket();
    const response = await fetch(
      `${storageRoot}/object/sign/${healthDocumentBucket}/${encodePath(objectKey)}`,
      {
        method: "POST",
        headers: headers("application/json"),
        body: JSON.stringify({ expiresIn: healthDocumentSignedUrlLifetimeSeconds }),
      },
    );
    if (!response.ok) throw unavailable();
    const payload = await response.json() as Record<string, unknown>;
    const signed = payload.signedURL ?? payload.signedUrl;
    if (typeof signed !== "string" || signed.length === 0) throw unavailable();
    if (signed.startsWith("http")) return signed;
    if (signed.startsWith("/storage/v1/")) {
      return `${supabaseUrl.replace(/\/+$/, "")}${signed}`;
    }
    return `${storageRoot}${signed.startsWith("/") ? "" : "/"}${signed}`;
  }

  async function remove(objectKey: string): Promise<void> {
    assertSafeObjectKey(objectKey);
    await ensurePrivateBucket();
    const response = await fetch(`${storageRoot}/object/${healthDocumentBucket}`, {
      method: "DELETE",
      headers: headers("application/json"),
      body: JSON.stringify({ prefixes: [objectKey] }),
    });
    if (!response.ok && response.status !== 404) throw unavailable();
  }

  return { upload, signedDownload, remove };
}

function isHeic(bytes: Uint8Array): boolean {
  if (bytes.length < 12 || bytes[4] !== 0x66 || bytes[5] !== 0x74 ||
    bytes[6] !== 0x79 || bytes[7] !== 0x70) return false;
  const brand = new TextDecoder().decode(bytes.slice(8, 12)).toLowerCase();
  return ["heic", "heix", "hevc", "hevx", "mif1", "msf1"].includes(brand);
}

function encodePath(value: string): string {
  return value.split("/").map(encodeURIComponent).join("/");
}

function assertSafeObjectKey(value: string): void {
  if (
    !/^[0-9a-f-]{36}\/[0-9a-f-]{36}\/[0-9a-f-]{36}\.(jpg|png|webp|heic|pdf)$/i.test(value) ||
    value.includes("..")
  ) {
    throw new ApiError(400, "health_document_path_invalid", "Document path is invalid.");
  }
}

function unavailable(): ApiError {
  return new ApiError(
    503,
    "health_document_storage_unavailable",
    "Health document storage is temporarily unavailable.",
  );
}

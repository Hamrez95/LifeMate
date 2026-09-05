import { ApiError } from "./validation.ts";

export const supportAttachmentBucket = "support-attachments";
export const supportAttachmentMaximumBytes = 10 * 1024 * 1024;
const signedUrlLifetimeSeconds = 10 * 60;

export type SupportAttachmentKind = {
  contentType:
    | "image/jpeg"
    | "image/png"
    | "image/webp"
    | "application/pdf"
    | "text/plain";
  extension: "jpg" | "png" | "webp" | "pdf" | "txt";
};

export type SupportAttachmentScanResult =
  | { status: "Available"; reasonCode: null }
  | { status: "Rejected" | "ScanError"; reasonCode: string };

export function validateSupportAttachment(
  bytes: Uint8Array,
  rawContentType: string,
): SupportAttachmentKind {
  if (bytes.length < 1 || bytes.length > supportAttachmentMaximumBytes) {
    throw new ApiError(
      413,
      "support_attachment_too_large",
      "Attachment must be between 1 byte and 10 MB.",
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
  const plain = type === "text/plain" && !bytes.includes(0);
  if (type === "image/jpeg" && jpeg) {
    return { contentType: "image/jpeg", extension: "jpg" };
  }
  if (type === "image/png" && png) {
    return { contentType: "image/png", extension: "png" };
  }
  if (type === "image/webp" && webp) {
    return { contentType: "image/webp", extension: "webp" };
  }
  if (type === "application/pdf" && pdf) {
    return { contentType: "application/pdf", extension: "pdf" };
  }
  if (plain) return { contentType: "text/plain", extension: "txt" };
  throw new ApiError(
    415,
    "support_attachment_invalid",
    "Attachment type or file signature is invalid.",
  );
}

export function createSupportAttachmentRuntimeFromEnvironment() {
  const supabaseUrl = (Deno.env.get("SUPABASE_URL") ?? "").trim();
  const serviceRoleKeyName = ["SUPABASE", "SERVICE", "ROLE", "KEY"].join("_");
  const serviceRoleKey = (Deno.env.get(serviceRoleKeyName) ?? "").trim();
  if (!supabaseUrl || !serviceRoleKey) return undefined;
  return createSupportAttachmentRuntime(supabaseUrl, serviceRoleKey);
}

export function createSupportAttachmentRuntime(
  supabaseUrl: string,
  serviceRoleKey: string,
) {
  const storageRoot = `${supabaseUrl.replace(/\/+$/, "")}/storage/v1`;
  const scannerUrl =
    (Deno.env.get("LIFEMATE_SUPPORT_ATTACHMENT_SCAN_URL") ?? "").trim();
  const scannerToken =
    (Deno.env.get("LIFEMATE_SUPPORT_ATTACHMENT_SCAN_TOKEN") ?? "").trim();
  let bucketPromise: Promise<void> | null = null;

  const storageHeaders = (contentType?: string): Record<string, string> => ({
    apikey: serviceRoleKey,
    authorization: `Bearer ${serviceRoleKey}`,
    ...(contentType ? { "content-type": contentType } : {}),
  });

  async function ensureBucket() {
    bucketPromise ??= (async () => {
      const current = await fetch(
        `${storageRoot}/bucket/${supportAttachmentBucket}`,
        { headers: storageHeaders() },
      );
      if (current.ok) return;
      if (current.status !== 400 && current.status !== 404) {
        throw storageUnavailable();
      }
      const created = await fetch(`${storageRoot}/bucket`, {
        method: "POST",
        headers: storageHeaders("application/json"),
        body: JSON.stringify({
          id: supportAttachmentBucket,
          name: supportAttachmentBucket,
          public: false,
          file_size_limit: supportAttachmentMaximumBytes,
          allowed_mime_types: [
            "image/jpeg",
            "image/png",
            "image/webp",
            "application/pdf",
            "text/plain",
          ],
        }),
      });
      if (!created.ok && created.status !== 409) throw storageUnavailable();
    })().catch((error) => {
      bucketPromise = null;
      throw error;
    });
    await bucketPromise;
  }

  async function upload(
    accountId: string,
    ticketId: string,
    messageId: string,
    bytes: Uint8Array,
    rawContentType: string,
  ) {
    const validated = validateSupportAttachment(bytes, rawContentType);
    await ensureBucket();
    const objectPath =
      `${accountId}/${ticketId}/${messageId}/${crypto.randomUUID()}.${validated.extension}`;
    assertSafePath(objectPath);
    const response = await fetch(
      `${storageRoot}/object/${supportAttachmentBucket}/${
        encodePath(objectPath)
      }`,
      {
        method: "POST",
        headers: {
          ...storageHeaders(validated.contentType),
          "x-upsert": "false",
          "cache-control": "no-store",
        },
        body: bytes.slice().buffer as ArrayBuffer,
      },
    );
    if (!response.ok) throw storageUnavailable();
    return { objectPath, ...validated };
  }

  async function scan(
    bytes: Uint8Array,
    contentType: string,
    fileName: string,
  ): Promise<SupportAttachmentScanResult> {
    if (!scannerUrl || !scannerToken) {
      return { status: "ScanError", reasonCode: "scanner_unconfigured" };
    }
    try {
      const response = await fetch(scannerUrl, {
        method: "POST",
        headers: {
          authorization: `Bearer ${scannerToken}`,
          "content-type": contentType,
          "x-file-name": encodeURIComponent(fileName),
        },
        body: bytes.slice().buffer as ArrayBuffer,
        signal: AbortSignal.timeout(15_000),
      });
      if (!response.ok) {
        return {
          status: "ScanError",
          reasonCode: `scanner_http_${response.status}`,
        };
      }
      const payload = await response.json().catch(() => null) as
        | Record<string, unknown>
        | null;
      if (payload?.clean === true) {
        return { status: "Available", reasonCode: null };
      }
      if (payload?.clean === false) {
        return { status: "Rejected", reasonCode: "malware_detected" };
      }
      return { status: "ScanError", reasonCode: "scanner_response_invalid" };
    } catch {
      return { status: "ScanError", reasonCode: "scanner_unavailable" };
    }
  }

  async function signedDownload(objectPath: string): Promise<string> {
    assertSafePath(objectPath);
    await ensureBucket();
    const response = await fetch(
      `${storageRoot}/object/sign/${supportAttachmentBucket}/${
        encodePath(objectPath)
      }`,
      {
        method: "POST",
        headers: storageHeaders("application/json"),
        body: JSON.stringify({ expiresIn: signedUrlLifetimeSeconds }),
      },
    );
    if (!response.ok) throw storageUnavailable();
    const payload = await response.json() as Record<string, unknown>;
    const signed = payload.signedURL ?? payload.signedUrl;
    if (typeof signed !== "string" || signed.length === 0) {
      throw storageUnavailable();
    }
    if (signed.startsWith("http")) return signed;
    if (signed.startsWith("/storage/v1/")) {
      return `${supabaseUrl.replace(/\/+$/, "")}${signed}`;
    }
    return `${storageRoot}${signed.startsWith("/") ? "" : "/"}${signed}`;
  }

  async function remove(objectPath: string) {
    assertSafePath(objectPath);
    await ensureBucket();
    const response = await fetch(
      `${storageRoot}/object/${supportAttachmentBucket}`,
      {
        method: "DELETE",
        headers: storageHeaders("application/json"),
        body: JSON.stringify({ prefixes: [objectPath] }),
      },
    );
    if (!response.ok && response.status !== 404) throw storageUnavailable();
  }

  return { upload, scan, signedDownload, remove };
}

function encodePath(value: string): string {
  return value.split("/").map(encodeURIComponent).join("/");
}

function assertSafePath(value: string) {
  if (
    !/^[0-9a-f-]{36}\/[0-9a-f-]{36}\/[0-9a-f-]{36}\/[0-9a-f-]{36}\.(jpg|png|webp|pdf|txt)$/i
      .test(value) || value.includes("..")
  ) {
    throw new ApiError(
      400,
      "support_attachment_path_invalid",
      "Attachment path is invalid.",
    );
  }
}

function storageUnavailable() {
  return new ApiError(
    503,
    "support_attachment_storage_unavailable",
    "Attachment storage is temporarily unavailable.",
  );
}

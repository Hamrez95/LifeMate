export const researchExportBucket = "research-exports";
const maximumArtifactBytes = 5 * 1024 * 1024;

export function createResearchExportStorage(
  supabaseUrl: string,
  serviceRoleKey: string,
  fetcher: typeof fetch = fetch,
) {
  const storageRoot = `${supabaseUrl.replace(/\/+$/, "")}/storage/v1`;
  let bucketPromise: Promise<void> | null = null;
  const headers = (contentType?: string): Record<string, string> => ({
    apikey: serviceRoleKey,
    authorization: `Bearer ${serviceRoleKey}`,
    ...(contentType ? { "content-type": contentType } : {}),
  });

  async function ensureBucket() {
    bucketPromise ??= (async () => {
      const current = await fetcher(`${storageRoot}/bucket/${researchExportBucket}`, {
        headers: headers(),
      });
      if (!current.ok) {
        throw new Error("research_export_storage_unavailable");
      }
      const payload = await current.json().catch(() => null) as Record<string, unknown> | null;
      if (!payload || payload.public !== false) {
        throw new Error("research_export_storage_misconfigured");
      }
    })().catch((error) => {
      bucketPromise = null;
      throw error;
    });
    await bucketPromise;
  }

  async function upload(input: {
    jobId: string;
    extension: "csv" | "xlsx";
    contentType: string;
    bytes: Uint8Array;
  }): Promise<string> {
    if (input.bytes.length < 1 || input.bytes.length > maximumArtifactBytes) {
      throw new Error("research_export_artifact_size_invalid");
    }
    if (!/^[0-9a-f-]{36}$/i.test(input.jobId)) {
      throw new Error("research_export_job_id_invalid");
    }
    await ensureBucket();
    const objectPath = `${input.jobId}.${input.extension}`;
    const response = await fetcher(
      `${storageRoot}/object/${researchExportBucket}/${encodeURIComponent(objectPath)}`,
      {
        method: "POST",
        headers: {
          ...headers(input.contentType),
          "x-upsert": "true",
          "cache-control": "no-store",
        },
        body: Uint8Array.from(input.bytes).buffer,
      },
    );
    if (!response.ok) throw new Error("research_export_storage_upload_failed");
    return objectPath;
  }

  async function signedDownload(objectPath: string, expiresInSeconds = 600) {
    if (!/^[0-9a-f-]{36}\.(csv|xlsx)$/i.test(objectPath)) {
      throw new Error("research_export_artifact_path_invalid");
    }
    if (!Number.isInteger(expiresInSeconds) || expiresInSeconds < 60 || expiresInSeconds > 900) {
      throw new Error("research_export_signed_url_expiry_invalid");
    }
    await ensureBucket();
    const response = await fetcher(
      `${storageRoot}/object/sign/${researchExportBucket}/${encodeURIComponent(objectPath)}`,
      {
        method: "POST",
        headers: headers("application/json"),
        body: JSON.stringify({ expiresIn: expiresInSeconds }),
      },
    );
    if (!response.ok) throw new Error("research_export_storage_sign_failed");
    const payload = await response.json() as Record<string, unknown>;
    const signed = payload.signedURL ?? payload.signedUrl;
    if (typeof signed !== "string" || signed.length === 0) {
      throw new Error("research_export_storage_sign_failed");
    }
    if (signed.startsWith("http")) return signed;
    if (signed.startsWith("/storage/v1/")) return `${supabaseUrl.replace(/\/+$/, "")}${signed}`;
    return `${storageRoot}${signed.startsWith("/") ? "" : "/"}${signed}`;
  }

  return { upload, signedDownload };
}

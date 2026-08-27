import { createResearchExportStorage } from "./research_export_storage.ts";

type SqlLike = any;
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export function createResearchExportSignerRoute(input: {
  sql: SqlLike;
  supabaseUrl: string;
  serviceRoleKey: string;
  signerToken: string | undefined;
  fetcher?: typeof fetch;
}) {
  const storage = createResearchExportStorage(
    input.supabaseUrl,
    input.serviceRoleKey,
    input.fetcher ?? fetch,
  );

  return async (request: Request): Promise<Response | null> => {
    const path = new URL(request.url).pathname;
    if (!path.endsWith("/research-export-download")) return null;
    if (request.method !== "POST") return response(405, { error: "method_not_allowed" });
    if (!input.signerToken || input.signerToken.length < 32) {
      return response(503, { error: "research_export_signer_not_configured" });
    }
    const supplied = request.headers.get("x-lifemate-research-signer-token") ?? "";
    if (!constantTimeEqual(input.signerToken, supplied)) {
      return response(401, { error: "unauthorized" });
    }
    const payload = await request.json().catch(() => null) as Record<string, unknown> | null;
    const actorAccountId = payload?.actorAccountId;
    const jobId = payload?.jobId;
    if (
      typeof actorAccountId !== "string" || !uuidPattern.test(actorAccountId) ||
      typeof jobId !== "string" || !uuidPattern.test(jobId)
    ) {
      return response(400, { error: "invalid_request" });
    }

    const rows = await input.sql`
      select * from analytics.get_research_export_download(
        ${actorAccountId}::uuid,${jobId}::uuid
      )
    `;
    const row = rows[0];
    if (!row) return response(404, { error: "research_export_download_unavailable" });
    const objectPath = String(row.storage_object_path ?? "");
    const signedUrl = await storage.signedDownload(objectPath, 600);
    return response(200, {
      signedUrl,
      expiresInSeconds: 600,
      artifactSha256: String(row.artifact_sha256),
      format: String(row.export_format),
      artifactExpiresAtUtc: new Date(String(row.artifact_expires_at_utc)).toISOString(),
    });
  };
}

function constantTimeEqual(expected: string, actual: string): boolean {
  const encoder = new TextEncoder();
  const a = encoder.encode(expected);
  const b = encoder.encode(actual);
  let difference = a.length ^ b.length;
  const length = Math.max(a.length, b.length);
  for (let i = 0; i < length; i++) {
    difference |= (a[i % a.length] ?? 0) ^ (b[i % Math.max(1, b.length)] ?? 0);
  }
  return difference === 0;
}

function response(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store",
    },
  });
}

import { assertEquals } from "jsr:@std/assert@1.0.14";
import { createResearchExportSignerRoute } from "./research_export_signer_route.ts";

const actorId = "00000000-0000-4000-8000-000000000003";
const jobId = "00000000-0000-4000-8000-000000000001";
const token = "r".repeat(32);

function createSql(row: Record<string, unknown> | null) {
  return async (_strings: TemplateStringsArray, ..._values: unknown[]) => row ? [row] : [];
}

function createFetcher() {
  return async (input: RequestInfo | URL, init?: RequestInit) => {
    const url = String(input);
    if (url.endsWith("/storage/v1/bucket/research-exports")) {
      return Response.json({ public: false });
    }
    if (url.includes("/storage/v1/object/sign/research-exports/")) {
      assertEquals(init?.method, "POST");
      return Response.json({ signedURL: "/storage/v1/object/sign/research-exports/signed-token" });
    }
    return new Response(null, { status: 404 });
  };
}

Deno.test("research signer route fails closed when signer token is missing", async () => {
  const route = createResearchExportSignerRoute({
    sql: createSql(null),
    supabaseUrl: "https://example.supabase.co",
    serviceRoleKey: "service-key",
    signerToken: undefined,
    fetcher: createFetcher(),
  });
  const response = await route(new Request(
    "https://worker.example/research-export-download",
    { method: "POST" },
  ));
  assertEquals(response?.status, 503);
});

Deno.test("research signer route rejects invalid worker credential", async () => {
  const route = createResearchExportSignerRoute({
    sql: createSql(null),
    supabaseUrl: "https://example.supabase.co",
    serviceRoleKey: "service-key",
    signerToken: token,
    fetcher: createFetcher(),
  });
  const response = await route(new Request(
    "https://worker.example/research-export-download",
    {
      method: "POST",
      headers: { "x-lifemate-research-signer-token": "wrong" },
    },
  ));
  assertEquals(response?.status, 401);
});

Deno.test("research signer route returns only a bounded signed artifact contract", async () => {
  const route = createResearchExportSignerRoute({
    sql: createSql({
      storage_object_path: `${jobId}.csv`,
      artifact_sha256: "a".repeat(64),
      export_format: "CSV",
      artifact_expires_at_utc: "2026-08-27T18:00:00Z",
    }),
    supabaseUrl: "https://example.supabase.co",
    serviceRoleKey: "service-key",
    signerToken: token,
    fetcher: createFetcher(),
  });
  const response = await route(new Request(
    "https://worker.example/research-export-download",
    {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-lifemate-research-signer-token": token,
      },
      body: JSON.stringify({ actorAccountId: actorId, jobId }),
    },
  ));
  assertEquals(response?.status, 200);
  const payload = await response?.json();
  assertEquals(payload.expiresInSeconds, 600);
  assertEquals(payload.artifactSha256, "a".repeat(64));
  assertEquals(payload.format, "CSV");
  assertEquals(
    payload.signedUrl,
    "https://example.supabase.co/storage/v1/object/sign/research-exports/signed-token",
  );
});
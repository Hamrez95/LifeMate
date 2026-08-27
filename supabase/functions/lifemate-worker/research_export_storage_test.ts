import { assertEquals, assertRejects } from "jsr:@std/assert@1.0.14";
import { createResearchExportStorage } from "./research_export_storage.ts";

Deno.test("research export storage requires a pre-provisioned private bucket", async () => {
  const calls: Array<{ url: string; init?: RequestInit }> = [];
  const fetcher: typeof fetch = async (input, init) => {
    const url = String(input);
    calls.push({ url, init });
    if (url.endsWith("/bucket/research-exports")) {
      return new Response(JSON.stringify({ id: "research-exports", public: false }), {
        status: 200,
        headers: { "content-type": "application/json" },
      });
    }
    return new Response("{}", { status: 200 });
  };
  const storage = createResearchExportStorage(
    "https://example.supabase.co",
    "service-key",
    fetcher,
  );
  const jobId = "00000000-0000-4000-8000-000000000001";
  assertEquals(await storage.upload({
    jobId,
    extension: "csv",
    contentType: "text/csv",
    bytes: new TextEncoder().encode("a,b\r\n1,2\r\n"),
  }), `${jobId}.csv`);
  assertEquals(calls.some((call) => call.url.endsWith("/bucket") && call.init?.method === "POST"), false);
  assertEquals(calls.at(-1)?.url.endsWith(`/research-exports/${jobId}.csv`), true);
});

Deno.test("research export storage fails closed when bucket is absent or public", async () => {
  const missing = createResearchExportStorage(
    "https://example.supabase.co",
    "service-key",
    async () => new Response("", { status: 404 }),
  );
  await assertRejects(() => missing.upload({
    jobId: "00000000-0000-4000-8000-000000000001",
    extension: "csv",
    contentType: "text/csv",
    bytes: new Uint8Array([1]),
  }));

  const publicBucket = createResearchExportStorage(
    "https://example.supabase.co",
    "service-key",
    async () => new Response(JSON.stringify({ public: true }), {
      status: 200,
      headers: { "content-type": "application/json" },
    }),
  );
  await assertRejects(() => publicBucket.upload({
    jobId: "00000000-0000-4000-8000-000000000001",
    extension: "csv",
    contentType: "text/csv",
    bytes: new Uint8Array([1]),
  }));
});

Deno.test("research export signed URL is bounded and private", async () => {
  const fetcher: typeof fetch = async (input) => {
    const url = String(input);
    if (url.endsWith("/bucket/research-exports")) {
      return new Response(JSON.stringify({ id: "research-exports", public: false }), {
        status: 200,
        headers: { "content-type": "application/json" },
      });
    }
    return new Response(JSON.stringify({ signedURL: "/storage/v1/object/sign/research-exports/x?token=test" }), {
      status: 200,
      headers: { "content-type": "application/json" },
    });
  };
  const storage = createResearchExportStorage("https://example.supabase.co", "service-key", fetcher);
  const url = await storage.signedDownload("00000000-0000-4000-8000-000000000001.csv", 600);
  assertEquals(url.startsWith("https://example.supabase.co/storage/v1/"), true);
  await assertRejects(() => storage.signedDownload("../secret.csv", 600));
  await assertRejects(() => storage.signedDownload("00000000-0000-4000-8000-000000000001.csv", 3600));
});

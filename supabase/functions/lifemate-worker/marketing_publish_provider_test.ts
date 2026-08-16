import { assertEquals } from "jsr:@std/assert@1";
import { publishMarketingContent } from "./marketing_publish_provider.ts";

const credential = JSON.stringify({
  botToken: "123456789:ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghi",
  chatId: "@lifemate_test",
});

Deno.test("ADM-MKT-003 unsupported social providers fail closed without calling network", async () => {
  let called = false;
  const result = await publishMarketingContent(
    { providerCode: "instagram", publishText: "hello", assetRefs: [], credentialSecret: "secret" },
    async () => {
      called = true;
      return new Response();
    },
  );
  assertEquals(called, false);
  assertEquals(result, { kind: "rejected", code: "provider_adapter_not_ready" });
});

Deno.test("ADM-MKT-003 Telegram publish returns privacy-minimized provider reference", async () => {
  const result = await publishMarketingContent(
    { providerCode: "telegram", publishText: "LifeMate launch", assetRefs: [], credentialSecret: credential },
    async (input, init) => {
      assertEquals(String(input).startsWith("https://api.telegram.org/bot"), true);
      assertEquals(init?.method, "POST");
      return Response.json({ ok: true, result: { message_id: 42 } });
    },
  );
  assertEquals(result, { kind: "published", providerPostRef: "telegram:42" });
});

Deno.test("ADM-MKT-003 ambiguous provider failures are not retry-safe", async () => {
  const result = await publishMarketingContent(
    { providerCode: "telegram", publishText: "LifeMate launch", assetRefs: [], credentialSecret: credential },
    async () => new Response("provider unavailable", { status: 503 }),
  );
  assertEquals(result, { kind: "unknown", code: "provider_ambiguous_503" });
});

Deno.test("ADM-MKT-003 malformed credentials and unsupported assets fail before side effect", async () => {
  const badCredential = await publishMarketingContent(
    { providerCode: "telegram", publishText: "LifeMate launch", assetRefs: [], credentialSecret: "not-json" },
    async () => {
      throw new Error("network must not be called");
    },
  );
  assertEquals(badCredential.kind, "rejected");

  const assetResult = await publishMarketingContent(
    { providerCode: "telegram", publishText: "LifeMate launch", assetRefs: ["asset:1"], credentialSecret: credential },
    async () => {
      throw new Error("network must not be called");
    },
  );
  assertEquals(assetResult, { kind: "rejected", code: "telegram_asset_publish_not_ready" });
});

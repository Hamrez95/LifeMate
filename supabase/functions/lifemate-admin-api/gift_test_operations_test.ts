import { assertEquals, assertRejects } from "jsr:@std/assert";
import { ApiError } from "./validation.ts";
import {
  hashGiftTestFinalizePayload,
  parseGiftTestFinalizePayload,
} from "./gift_test_operations.ts";

Deno.test("gift test finalize accepts only canonical ids and hashed claim token", async () => {
  const request = new Request("https://example.test", {
    method: "POST",
    body: JSON.stringify({
      giftIntentId: "11111111-1111-4111-8111-111111111111",
      transactionId: "22222222-2222-4222-8222-222222222222",
      claimTokenHash: "a".repeat(64),
      claimTtlHours: 168,
    }),
  });
  const payload = await parseGiftTestFinalizePayload(request);
  assertEquals(payload.claimTokenHash, "a".repeat(64));
  assertEquals(payload.claimTtlHours, 168);
  assertEquals((await hashGiftTestFinalizePayload(payload)).length, 64);
});

Deno.test("gift test finalize rejects raw or malformed claim tokens", async () => {
  await assertRejects(
    () =>
      parseGiftTestFinalizePayload(
        new Request("https://example.test", {
          method: "POST",
          body: JSON.stringify({
            giftIntentId: "11111111-1111-4111-8111-111111111111",
            transactionId: "22222222-2222-4222-8222-222222222222",
            claimTokenHash: "raw-gift-token",
          }),
        }),
      ),
    ApiError,
    "claimTokenHash is invalid",
  );
});

Deno.test("gift test finalization hash changes when transaction changes", async () => {
  const base = {
    giftIntentId: "11111111-1111-4111-8111-111111111111",
    transactionId: "22222222-2222-4222-8222-222222222222",
    claimTokenHash: "b".repeat(64),
    claimTtlHours: 168,
  };
  const first = await hashGiftTestFinalizePayload(base);
  const second = await hashGiftTestFinalizePayload({
    ...base,
    transactionId: "33333333-3333-4333-8333-333333333333",
  });
  assertEquals(first === second, false);
});

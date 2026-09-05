import {
  parseAdvocacyPayload,
  parseGiftPayload,
  parseReferralPayload,
} from "./growth.ts";
import { createHmac } from "./security.ts";

function assert(condition: boolean, message: string): void {
  if (!condition) throw new Error(message);
}

async function expectReject(
  run: () => unknown | Promise<unknown>,
  code: string,
): Promise<void> {
  try {
    await run();
  } catch (error) {
    assert(
      typeof error === "object" && error !== null &&
        "code" in error && (error as { code?: string }).code === code,
      `Expected ${code}.`,
    );
    return;
  }
  throw new Error(`Expected ${code}.`);
}

Deno.test("gift payload canonicalizes Iranian phone and target", () => {
  const payload = parseGiftPayload({
    recipientPhone: "0912 123 4567",
    targetKind: "Offer",
    targetId: "123e4567-e89b-42d3-a456-426614174000",
  });
  assert(payload.recipientPhone === "+989121234567", "phone must be E.164");
  assert(payload.targetKind === "Offer", "target kind must survive");
  assert(
    payload.targetId === "123e4567-e89b-42d3-a456-426614174000",
    "target id must be canonical",
  );
});

Deno.test("gift payload rejects invalid target and phone", async () => {
  await expectReject(
    () =>
      parseGiftPayload({
        recipientPhone: "123",
        targetKind: "Offer",
        targetId: "123e4567-e89b-42d3-a456-426614174000",
      }),
    "gift_recipient_phone_invalid",
  );
  await expectReject(
    () =>
      parseGiftPayload({
        recipientPhone: "09121234567",
        targetKind: "Product",
        targetId: "123e4567-e89b-42d3-a456-426614174000",
      }),
    "gift_target_invalid",
  );
});

Deno.test("referral payload is strict and canonical", async () => {
  assert(
    parseReferralPayload({ code: "ab12cd34" }) === "AB12CD34",
    "code uppercase",
  );
  await expectReject(
    () => parseReferralPayload({ code: "bad-code" }),
    "referral_code_invalid",
  );
});

Deno.test("advocacy payload is bounded and explicit", async () => {
  const payload = parseAdvocacyPayload({
    platformCode: "Instagram",
    evidenceType: "PostUrl",
    evidenceReference: "https://example.invalid/post/123",
  });
  assert(payload.platformCode === "instagram", "platform must canonicalize");
  assert(payload.evidenceType === "PostUrl", "evidence type must survive");
  await expectReject(
    () =>
      parseAdvocacyPayload({
        platformCode: "instagram",
        evidenceType: "ScrapedProfile",
        evidenceReference: "private-profile",
      }),
    "advocacy_evidence_type_invalid",
  );
  await expectReject(
    () =>
      parseAdvocacyPayload({
        platformCode: "instagram",
        evidenceType: "PostUrl",
        evidenceReference: "x".repeat(2049),
      }),
    "growth_request_invalid",
  );
});

Deno.test("advocacy evidence reference is privacy-hashed", async () => {
  const raw = "https://social.example/private-or-public-reference/123";
  const hmac = createHmac("0123456789abcdef0123456789abcdef");
  const first = await hmac(`advocacy-evidence:v1|instagram|${raw}`);
  const second = await hmac(`advocacy-evidence:v1|instagram|${raw}`);
  assert(first === second, "evidence hash must be deterministic");
  assert(/^[0-9a-f]{64}$/.test(first), "evidence hash must be SHA-256 HMAC");
  assert(!first.includes(raw), "raw evidence reference must not be retained");
});

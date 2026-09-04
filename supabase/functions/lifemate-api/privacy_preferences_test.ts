import { assertEquals, assertThrows } from "jsr:@std/assert@1.0.14";
import {
  parseLegalAcceptances,
  parsePrivacyPreferencePayload,
} from "./privacy_preferences.ts";
import { ApiError } from "./validation.ts";

Deno.test("legal acceptance parser accepts bounded document evidence", () => {
  assertEquals(
    parseLegalAcceptances([{
      documentId: "018f5e6a-7e91-4c26-8e18-a83c5531d111",
      documentHash: "sha256:0123456789abcdef0123456789abcdef",
    }]),
    [{
      documentId: "018f5e6a-7e91-4c26-8e18-a83c5531d111",
      documentHash: "sha256:0123456789abcdef0123456789abcdef",
    }],
  );
});

Deno.test("legal acceptance parser rejects duplicate documents", () => {
  const error = assertThrows(() =>
    parseLegalAcceptances([
      {
        documentId: "018f5e6a-7e91-4c26-8e18-a83c5531d111",
        documentHash: "sha256:0123456789abcdef0123456789abcdef",
      },
      {
        documentId: "018f5e6a-7e91-4c26-8e18-a83c5531d111",
        documentHash: "sha256:0123456789abcdef0123456789abcdef",
      },
    ])
  );
  assertEquals(error instanceof ApiError, true);
  assertEquals((error as ApiError).code, "legal_acceptance_duplicate");
});

Deno.test("privacy preference parser requires explicit boolean and safe purpose", () => {
  assertEquals(
    parsePrivacyPreferencePayload({
      purpose: "Promotional_SMS",
      enabled: false,
    }),
    {
      purpose: "promotional_sms",
      enabled: false,
    },
  );

  const error = assertThrows(() =>
    parsePrivacyPreferencePayload({
      purpose: "promotional_sms",
      enabled: "false",
    })
  );
  assertEquals(error instanceof ApiError, true);
  assertEquals((error as ApiError).code, "privacy_preference_invalid");
});

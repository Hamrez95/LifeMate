import { assertEquals, assertThrows } from "jsr:@std/assert@1.0.14";
import { parseLegalAcceptances } from "./privacy_preferences.ts";
import { ApiError } from "./validation.ts";

Deno.test("registration legal evidence is bounded and exact", () => {
  const parsed = parseLegalAcceptances([
    {
      documentId: "018f5e6a-7e91-4c26-8e18-a83c5531d111",
      documentHash: "sha256:0123456789abcdef0123456789abcdef",
    },
  ]);
  assertEquals(parsed.length, 1);
  assertEquals(parsed[0].documentId, "018f5e6a-7e91-4c26-8e18-a83c5531d111");
});

Deno.test("registration legal evidence rejects oversized acceptance sets", () => {
  const items = Array.from({ length: 9 }, (_, index) => ({
    documentId: `018f5e6a-7e91-4c26-8e18-a83c5531d1${
      index.toString().padStart(2, "0")
    }`,
    documentHash: "sha256:0123456789abcdef0123456789abcdef",
  }));
  const error = assertThrows(() => parseLegalAcceptances(items));
  assertEquals(error instanceof ApiError, true);
  assertEquals((error as ApiError).code, "legal_acceptance_invalid");
});

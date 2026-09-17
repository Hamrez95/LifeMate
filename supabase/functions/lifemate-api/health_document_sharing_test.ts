import { assertEquals, assertThrows } from "jsr:@std/assert@1.0.14";
import {
  healthDocumentSharingConsentVersion,
  parseHealthDocumentSharingUpdate,
} from "./health_document_sharing.ts";
import { ApiError } from "./validation.ts";

Deno.test("Health Record document sharing uses the versioned explicit consent contract", () => {
  assertEquals(
    healthDocumentSharingConsentVersion,
    "health-record-documents-sharing-v1",
  );
  assertEquals(
    parseHealthDocumentSharingUpdate({
      canViewDocuments: true,
      confirmConsent: true,
      consentVersion: healthDocumentSharingConsentVersion,
    }),
    {
      canViewDocuments: true,
      confirmConsent: true,
      consentVersion: healthDocumentSharingConsentVersion,
    },
  );
});

Deno.test("Health Record document sharing revoke does not require a fresh consent", () => {
  assertEquals(
    parseHealthDocumentSharingUpdate({ canViewDocuments: false }),
    {
      canViewDocuments: false,
      confirmConsent: false,
      consentVersion: null,
    },
  );
});

Deno.test("Health Record document sharing rejects malformed permission state", () => {
  const error = assertThrows(() =>
    parseHealthDocumentSharingUpdate({ canViewDocuments: "yes" })
  );
  assertEquals(error instanceof ApiError, true);
  assertEquals((error as ApiError).code, "health_document_sharing_invalid");
});

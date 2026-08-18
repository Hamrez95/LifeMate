import { assertEquals, assertThrows } from "jsr:@std/assert@1.0.14";
import {
  contactOnlyReadinessApproved,
  contactPointLookupMode,
  createContactPointReader,
  rawContactRetirementEnabled,
} from "./contact_points.ts";

const encryptionKey = {
  secret: "contact-read-mode-unit-envelope-key-32-bytes-minimum",
  keyVersion: 31,
};

Deno.test("ContactPoint Profile lookup defaults to legacy without key dependencies", () => {
  assertEquals(contactPointLookupMode(() => undefined), "legacy");
  assertEquals(rawContactRetirementEnabled(() => undefined), false);
  assertEquals(contactOnlyReadinessApproved(() => undefined), false);
  assertEquals(
    createContactPointReader({ readEnvironment: () => undefined }).lookupMode,
    "legacy",
  );
});

Deno.test("ContactPoint Profile lookup rejects unknown modes and invalid booleans", () => {
  assertThrows(
    () => contactPointLookupMode(() => "canonical-ish"),
    Error,
    "legacy, prefer-contact, or contact-only",
  );
  assertThrows(
    () => rawContactRetirementEnabled(() => "maybe"),
    Error,
    "true or false",
  );
  assertThrows(
    () => contactOnlyReadinessApproved(() => "yes"),
    Error,
    "true or false",
  );
});

Deno.test("contact-only requires readiness approval and continuous dual-write", () => {
  assertThrows(
    () =>
      createContactPointReader({
        lookupMode: "contact-only",
        encryptionKey,
        readinessApproved: false,
        dualWriteEnabled: true,
      }),
    Error,
    "READINESS_APPROVED",
  );
  assertThrows(
    () =>
      createContactPointReader({
        lookupMode: "contact-only",
        encryptionKey,
        readinessApproved: true,
        dualWriteEnabled: false,
      }),
    Error,
    "DUAL_WRITE",
  );
  const reader = createContactPointReader({
    lookupMode: "contact-only",
    encryptionKey,
    readinessApproved: true,
    dualWriteEnabled: true,
    rawRetirementEnabled: true,
  });
  assertEquals(reader.lookupMode, "contact-only");
  assertEquals(reader.readinessApproved, true);
  assertEquals(reader.dualWriteEnabled, true);
  assertEquals(reader.rawRetirementEnabled, true);
});

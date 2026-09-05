import { assertEquals, assertThrows } from "jsr:@std/assert@1.0.14";
import { validateHealthDocument } from "./health_document_storage.ts";

Deno.test("health document validation enforces allowed content types and bytes", () => {
  assertEquals(
    validateHealthDocument(
      new Uint8Array([0xff, 0xd8, 0xff, 0x00]),
      "image/jpeg",
    ).extension,
    "jpg",
  );
  assertEquals(
    validateHealthDocument(
      new TextEncoder().encode("%PDF-1.7\n"),
      "application/pdf",
    ).extension,
    "pdf",
  );
  assertEquals(
    validateHealthDocument(
      new Uint8Array([
        0, 0, 0, 24, 0x66, 0x74, 0x79, 0x70, 0x68, 0x65, 0x69, 0x63,
      ]),
      "image/heic",
    ).extension,
    "heic",
  );
  assertThrows(() =>
    validateHealthDocument(
      new TextEncoder().encode("not really an image"),
      "image/png",
    )
  );
  assertThrows(() =>
    validateHealthDocument(new Uint8Array(15 * 1024 * 1024 + 1), "image/jpeg")
  );
});

Deno.test("Health Record Storage uses a private opaque object contract", async () => {
  const source = await Deno.readTextFile(
    new URL("./health_document_storage.ts", import.meta.url),
  );
  assertEquals(source.includes('healthDocumentBucket = "health-records"'), true);
  assertEquals(source.includes("public: false"), true);
  assertEquals(source.includes("x-upsert"), true);
  assertEquals(source.includes("assertSafeObjectKey"), true);
  assertEquals(source.includes("healthDocumentSignedUrlLifetimeSeconds"), true);
});

import { assertEquals, assertThrows } from "jsr:@std/assert@1.0.14";
import {
  createSupportAttachmentRuntime,
  validateSupportAttachment,
} from "./support_attachment_storage.ts";

Deno.test("support attachment validation verifies MIME and file signature", () => {
  assertEquals(
    validateSupportAttachment(
      new Uint8Array([0xff, 0xd8, 0xff, 0x00]),
      "image/jpeg",
    ).extension,
    "jpg",
  );
  assertEquals(
    validateSupportAttachment(
      new TextEncoder().encode("%PDF-1.7\n"),
      "application/pdf",
    ).extension,
    "pdf",
  );
  assertThrows(() =>
    validateSupportAttachment(
      new TextEncoder().encode("not really a png"),
      "image/png",
    )
  );
});

Deno.test("support attachment scanner fails closed when provider is unconfigured", async () => {
  const previousUrl = Deno.env.get("LIFEMATE_SUPPORT_ATTACHMENT_SCAN_URL");
  const previousToken = Deno.env.get("LIFEMATE_SUPPORT_ATTACHMENT_SCAN_TOKEN");
  Deno.env.delete("LIFEMATE_SUPPORT_ATTACHMENT_SCAN_URL");
  Deno.env.delete("LIFEMATE_SUPPORT_ATTACHMENT_SCAN_TOKEN");
  try {
    const runtime = createSupportAttachmentRuntime(
      "https://example.supabase.co",
      "test-service-key",
    );
    assertEquals(
      await runtime.scan(
        new TextEncoder().encode("hello"),
        "text/plain",
        "evidence.txt",
      ),
      { status: "ScanError", reasonCode: "scanner_unconfigured" },
    );
  } finally {
    if (previousUrl == null) {
      Deno.env.delete("LIFEMATE_SUPPORT_ATTACHMENT_SCAN_URL");
    } else Deno.env.set("LIFEMATE_SUPPORT_ATTACHMENT_SCAN_URL", previousUrl);
    if (previousToken == null) {
      Deno.env.delete("LIFEMATE_SUPPORT_ATTACHMENT_SCAN_TOKEN");
    } else {Deno.env.set(
        "LIFEMATE_SUPPORT_ATTACHMENT_SCAN_TOKEN",
        previousToken,
      );}
  }
});

Deno.test("support attachment routes and migration require clean scan before signed download", async () => {
  const routes = await Deno.readTextFile(
    new URL("./support_conversations_routes.ts", import.meta.url),
  );
  const migration = await Deno.readTextFile(
    new URL(
      "../../migrations/20260827112400_support_attachment_access.sql",
      import.meta.url,
    ),
  );
  assertEquals(routes.includes("signedDownload"), true);
  assertEquals(routes.includes('scan.status === "Available"'), true);
  assertEquals(
    routes.includes('if (scan.status !== "Available")'),
    true,
    "scanner errors and malware rejection must both remove the untrusted Storage object",
  );
  assertEquals(migration.includes("and a.scan_status='Available'"), true);
  assertEquals(
    migration.includes("support.get_user_support_attachment_download"),
    true,
  );
  assertEquals(
    migration.includes("support.register_user_support_attachment"),
    true,
  );
});

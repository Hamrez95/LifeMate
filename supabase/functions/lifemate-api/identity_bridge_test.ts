import { assertEquals, assertThrows } from "jsr:@std/assert@1.0.14";
import { identityLinkDualWriteEnabled } from "./identity_bridge.ts";

Deno.test("identity token dual-write is fail-closed by default", () => {
  assertEquals(identityLinkDualWriteEnabled(() => undefined), false);
  assertEquals(
    identityLinkDualWriteEnabled((name) =>
      name === "LIFEMATE_IDENTITY_LINK_DUAL_WRITE" ? "false" : undefined
    ),
    false,
  );
});

Deno.test("identity token dual-write requires explicit true", () => {
  assertEquals(
    identityLinkDualWriteEnabled((name) =>
      name === "LIFEMATE_IDENTITY_LINK_DUAL_WRITE" ? " true " : undefined
    ),
    true,
  );
  assertThrows(
    () =>
      identityLinkDualWriteEnabled((name) =>
        name === "LIFEMATE_IDENTITY_LINK_DUAL_WRITE" ? "1" : undefined
      ),
    Error,
    "must be either true or false",
  );
});

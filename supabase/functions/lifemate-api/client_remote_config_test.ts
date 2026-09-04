import { assertEquals, assertThrows } from "jsr:@std/assert";
import { parseClientRuntimeConfigQuery } from "./client_remote_config.ts";

Deno.test("client runtime config accepts bounded product platform version and beta", () => {
  const url = new URL(
    "https://example.test/api/v1/product/runtime-config?product=WellMate&platform=android&currentVersion=1.2.3-beta.1%2B42&beta=true",
  );
  assertEquals(parseClientRuntimeConfigQuery(url), {
    product: "wellmate",
    platform: "android",
    currentVersion: "1.2.3-beta.1+42",
    beta: true,
  });
});

Deno.test("client runtime config accepts CocoonMate as a canonical product", () => {
  const url = new URL(
    "https://example.test/api/v1/product/runtime-config?product=CocoonMate&platform=android&currentVersion=0.1.0%2B1&beta=false",
  );
  assertEquals(parseClientRuntimeConfigQuery(url), {
    product: "cocoonmate",
    platform: "android",
    currentVersion: "0.1.0+1",
    beta: false,
  });
});

Deno.test("client runtime config rejects unknown products", () => {
  const url = new URL(
    "https://example.test/api/v1/product/runtime-config?product=unknown&platform=android&currentVersion=1.2.3",
  );
  assertThrows(() => parseClientRuntimeConfigQuery(url));
});

Deno.test("client runtime config rejects malformed versions", () => {
  const url = new URL(
    "https://example.test/api/v1/product/runtime-config?product=caremate&platform=android&currentVersion=latest",
  );
  assertThrows(() => parseClientRuntimeConfigQuery(url));
});

Deno.test("client runtime config rejects arbitrary beta values", () => {
  const url = new URL(
    "https://example.test/api/v1/product/runtime-config?product=caremate&platform=android&currentVersion=1.0.0&beta=yes",
  );
  assertThrows(() => parseClientRuntimeConfigQuery(url));
});

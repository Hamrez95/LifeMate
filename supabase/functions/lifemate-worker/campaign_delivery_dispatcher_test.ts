import {
  assert,
  assertFalse,
  assertStringIncludes,
} from "jsr:@std/assert@1.0.14";

Deno.test("worker dispatcher wires campaign delivery without exposing recipient payloads", async () => {
  const source = await Deno.readTextFile(new URL("./index.ts", import.meta.url));

  assertStringIncludes(
    source,
    'import { createCampaignDeliveryRuntime } from "./campaign_delivery_runtime.ts";',
  );
  assertStringIncludes(source, "campaignDeliveryRuntime.run(workerBatchSize)");
  assertStringIncludes(source, "campaignDeliveryConfigurationError = safeErrorCode(error)");
  assertStringIncludes(source, "campaignDelivery,");

  // The dispatcher may expose aggregate counters only. Recipient endpoints and
  // decrypted provider payloads stay encapsulated in the delivery runtime.
  assertFalse(source.includes("endpointCiphertextB64"));
  assertFalse(source.includes("phoneE164"));
  assertFalse(source.includes("token:"));

  // A campaign-provider/configuration fault must not take down the shared
  // healthcare worker dispatcher.
  assert(source.includes("Campaign delivery runtime configuration is unavailable"));
});

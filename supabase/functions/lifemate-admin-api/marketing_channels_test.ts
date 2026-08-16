import {
  assertEquals,
  assertNotEquals,
  assertRejects,
  assertThrows,
} from "jsr:@std/assert@1";

import {
  hashMarketingChannelStatusRequest,
  MARKETING_CHANNEL_SETUP_STATUSES,
  matchMarketingChannelStatusPath,
  parseMarketingChannelStatusPayload,
} from "./marketing_channels.ts";

Deno.test("ADM-MKT-005 setup states do not claim unverified provider connectivity", () => {
  assertEquals(MARKETING_CHANNEL_SETUP_STATUSES, [
    "SetupRequired",
    "CredentialAvailable",
    "Disabled",
  ]);
});

Deno.test("ADM-MKT-005 channel status path accepts only bounded provider codes", () => {
  assertEquals(
    matchMarketingChannelStatusPath(
      "/api/v1/marketing/channels/Instagram/actions/status",
    ),
    "instagram",
  );
  assertThrows(() =>
    matchMarketingChannelStatusPath(
      "/api/v1/marketing/channels/../../vault/actions/status",
    )
  );
});

Deno.test("ADM-MKT-005 channel mutation requires boolean state and audit reason", async () => {
  const payload = await parseMarketingChannelStatusPayload(
    new Request(
      "https://admin.test/api/v1/marketing/channels/instagram/actions/status",
      {
        method: "POST",
        body: JSON.stringify({
          enabled: false,
          reason: "Temporarily disable outbound publishing for review.",
        }),
      },
    ),
  );
  assertEquals(payload.enabled, false);

  await assertRejects(() =>
    parseMarketingChannelStatusPayload(
      new Request(
        "https://admin.test/api/v1/marketing/channels/instagram/actions/status",
        {
          method: "POST",
          body: JSON.stringify({ enabled: "yes", reason: "too short" }),
        },
      ),
    )
  );
});

Deno.test("ADM-MKT-005 idempotency hash binds provider and operator state", async () => {
  const off = await hashMarketingChannelStatusRequest("instagram", {
    enabled: false,
    reason: "Temporarily disable outbound publishing for review.",
  });
  const on = await hashMarketingChannelStatusRequest("instagram", {
    enabled: true,
    reason: "Re-enable outbound publishing after security review.",
  });
  assertEquals(off.length, 64);
  assertEquals(on.length, 64);
  assertNotEquals(off, on);
});

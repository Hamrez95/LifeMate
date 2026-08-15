import { assertEquals, assertThrows } from "jsr:@std/assert@1";

import {
  MARKETING_CAMPAIGN_STATUSES,
  parseMarketingCampaignQuery,
} from "./marketing_campaigns.ts";

Deno.test("ADM-MKT-002 campaign query uses bounded pagination", () => {
  const query = parseMarketingCampaignQuery(
    new URL("https://admin.test/api/v1/marketing/campaigns?page=100&pageSize=100&status=Active&product=wellmate"),
  );

  assertEquals(query.page, 100);
  assertEquals(query.pageSize, 100);
  assertEquals(query.offset, 9900);
  assertEquals(query.status, "Active");
  assertEquals(query.product, "wellmate");
});

Deno.test("ADM-MKT-002 campaign query rejects deep pages and invalid workflow states", () => {
  assertThrows(() =>
    parseMarketingCampaignQuery(
      new URL("https://admin.test/api/v1/marketing/campaigns?page=101&pageSize=25"),
    )
  );
  assertThrows(() =>
    parseMarketingCampaignQuery(
      new URL("https://admin.test/api/v1/marketing/campaigns?status=Published"),
    )
  );
});

Deno.test("ADM-MKT-002 campaign workflow does not collapse provider publishing into campaign state", () => {
  assertEquals(MARKETING_CAMPAIGN_STATUSES, [
    "Draft",
    "Ready",
    "Active",
    "Paused",
    "Completed",
    "Cancelled",
  ]);
});

import { assertEquals } from "jsr:@std/assert@1.0.14";
import {
  maskIranianMobileE164,
  normalizeIranianMobileE164,
} from "./iran_phone.ts";

Deno.test("Iranian mobile variants normalize to canonical E.164", () => {
  for (
    const input of [
      "0912 123 4567",
      "9121234567",
      "+989121234567",
      "989121234567",
      "00989121234567",
      "۰۹۱۲۱۲۳۴۵۶۷",
      "٠٩١٢١٢٣٤٥٦٧",
    ]
  ) {
    assertEquals(normalizeIranianMobileE164(input), "+989121234567");
  }
});

Deno.test("Iranian mobile normalization rejects foreign, landline and malformed values", () => {
  for (
    const input of [
      "+491701234567",
      "+982112345678",
      "02112345678",
      "0912123456",
      "091212345678",
      "not-a-phone",
    ]
  ) {
    assertEquals(normalizeIranianMobileE164(input), null);
  }
});

Deno.test("Iranian mobile hint exposes only the final four digits", () => {
  assertEquals(maskIranianMobileE164("+989351234999"), "+98 ••• •• 4999");
});

import { assertEquals } from "jsr:@std/assert@1.0.14";
import { classifyCocoonCommerceEligibility } from "./cocoon_application.ts";

Deno.test("Cocoon Commerce eligibility keeps unavailable, entitlement, conversion and offer states distinct", () => {
  assertEquals(
    classifyCocoonCommerceEligibility({
      productAvailable: false,
      entitled: false,
      offerAvailable: true,
      conversionEligible: true,
    }),
    { state: "unavailable", offerAvailable: false, conversionEligible: false },
  );
  assertEquals(
    classifyCocoonCommerceEligibility({
      productAvailable: true,
      entitled: true,
      offerAvailable: true,
      conversionEligible: true,
    }),
    { state: "entitled", offerAvailable: true, conversionEligible: false },
  );
  assertEquals(
    classifyCocoonCommerceEligibility({
      productAvailable: true,
      entitled: false,
      offerAvailable: false,
      conversionEligible: true,
    }),
    {
      state: "conversion_eligible",
      offerAvailable: false,
      conversionEligible: true,
    },
  );
  assertEquals(
    classifyCocoonCommerceEligibility({
      productAvailable: true,
      entitled: false,
      offerAvailable: true,
      conversionEligible: false,
    }),
    { state: "offer_available", offerAvailable: true, conversionEligible: false },
  );
  assertEquals(
    classifyCocoonCommerceEligibility({
      productAvailable: true,
      entitled: false,
      offerAvailable: false,
      conversionEligible: false,
    }),
    { state: "not_entitled", offerAvailable: false, conversionEligible: false },
  );
  assertEquals(
    classifyCocoonCommerceEligibility({
      productAvailable: true,
      entitled: true,
      offerAvailable: true,
      conversionEligible: true,
      dependencyError: true,
    }),
    { state: "error", offerAvailable: false, conversionEligible: false },
  );
});

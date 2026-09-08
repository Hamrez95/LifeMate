import { assertEquals, assertThrows } from "jsr:@std/assert@1.0.14";
import {
  requireCocoonPregnancyActivationEntitlement,
  requiresCocoonPregnancyActivationEntitlement,
} from "./cocoon_routes.ts";
import { ApiError } from "./validation.ts";

Deno.test("Cocoon entitlement is rechecked only for pregnancy activation mutations", () => {
  assertEquals(
    requiresCocoonPregnancyActivationEntitlement(
      "POST",
      "/api/v1/cocoon/pregnancy/episodes",
    ),
    true,
  );
  assertEquals(
    requiresCocoonPregnancyActivationEntitlement(
      "POST",
      "/api/v1/cocoon/pregnancy/episodes/11111111-1111-4111-8111-111111111111/activate",
    ),
    true,
  );
  assertEquals(
    requiresCocoonPregnancyActivationEntitlement(
      "POST",
      "/api/v1/cocoon/pregnancy/episodes/11111111-1111-4111-8111-111111111111/end",
    ),
    false,
  );
  assertEquals(
    requiresCocoonPregnancyActivationEntitlement(
      "GET",
      "/api/v1/cocoon/pregnancy/episodes",
    ),
    false,
  );
});

Deno.test("Cocoon pregnancy activation allows only an entitled commerce snapshot", () => {
  requireCocoonPregnancyActivationEntitlement({
    state: "entitled",
    offerAvailable: false,
    conversionEligible: false,
  });

  const denied = assertThrows(
    () =>
      requireCocoonPregnancyActivationEntitlement({
        state: "offer_available",
        offerAvailable: true,
        conversionEligible: false,
      }),
    ApiError,
  );
  assertEquals(denied.status, 403);
  assertEquals(denied.code, "cocoon_entitlement_required");

  const unavailable = assertThrows(
    () =>
      requireCocoonPregnancyActivationEntitlement({
        state: "error",
        offerAvailable: false,
        conversionEligible: false,
      }),
    ApiError,
  );
  assertEquals(unavailable.status, 503);
  assertEquals(unavailable.code, "cocoon_commerce_unavailable");
});

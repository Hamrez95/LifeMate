import { assertEquals, assertThrows } from "jsr:@std/assert@1.0.14";
import { ApiError } from "./validation.ts";
import { normalizeProfilePatch } from "./profile.ts";

Deno.test("profile patch normalizes phone and preserves explicit locale/timezone", () => {
  assertEquals(
    normalizeProfilePatch({
      version: 3,
      displayName: " ریحانه شکیبا ",
      phoneNumber: "+98 (912) 123-4567",
      locale: "fa",
      timeZone: "Asia/Tehran",
    }),
    {
      expectedVersion: 3,
      displayName: "ریحانه شکیبا",
      phoneNumber: "+989121234567",
      locale: "fa",
      timeZone: "Asia/Tehran",
    },
  );
});

Deno.test("profile patch permits clearing the optional phone number", () => {
  assertEquals(
    normalizeProfilePatch({
      version: 1,
      displayName: "Owner",
      phoneNumber: "",
      locale: "en-US",
      timeZone: "Europe/Berlin",
    }).phoneNumber,
    null,
  );
});

Deno.test("profile patch rejects stale-shape and invalid identity fields", () => {
  for (
    const body of [
      {
        version: 0,
        displayName: "Owner",
        locale: "fa",
        timeZone: "Asia/Tehran",
      },
      {
        version: 1,
        displayName: "",
        locale: "fa",
        timeZone: "Asia/Tehran",
      },
      {
        version: 1,
        displayName: "Owner",
        phoneNumber: "not-a-phone",
        locale: "fa",
        timeZone: "Asia/Tehran",
      },
      {
        version: 1,
        displayName: "Owner",
        locale: "persian",
        timeZone: "Asia/Tehran",
      },
      {
        version: 1,
        displayName: "Owner",
        locale: "fa",
        timeZone: "Invalid/Zone",
      },
    ]
  ) {
    assertThrows(() => normalizeProfilePatch(body), ApiError);
  }
});

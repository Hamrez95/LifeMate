import { assertEquals, assertThrows } from "jsr:@std/assert@1.0.14";
import { ApiError } from "./validation.ts";
import { normalizeProfilePatch } from "./profile.ts";

Deno.test("profile patch normalizes phone and persists an allow-listed avatar", () => {
  assertEquals(
    normalizeProfilePatch({
      version: 3,
      displayName: " ریحانه شکیبا ",
      phoneNumber: "+98 (912) 123-4567",
      locale: "fa",
      timeZone: "Asia/Tehran",
      avatarKey: "person_purple",
    }),
    {
      expectedVersion: 3,
      displayName: "ریحانه شکیبا",
      phoneNumber: "+989121234567",
      locale: "fa",
      timeZone: "Asia/Tehran",
      avatarKey: "person_purple",
      presentationIntent: null,
      completeOnboarding: false,
      wellMateFirstValueState: null,
    },
  );
});

Deno.test("profile patch permits legacy clients and clearing the optional phone", () => {
  const patch = normalizeProfilePatch({
    version: 1,
    displayName: "Owner",
    phoneNumber: "",
    locale: "en-US",
    timeZone: "Europe/Berlin",
  });
  assertEquals(patch.phoneNumber, null);
  assertEquals(patch.avatarKey, null);
  assertEquals(patch.presentationIntent, null);
  assertEquals(patch.completeOnboarding, false);
  assertEquals(patch.wellMateFirstValueState, null);
});

Deno.test("WellMate first-value state is presentation-only and allow-listed", () => {
  assertEquals(
    normalizeProfilePatch({
      version: 2,
      displayName: "Owner",
      locale: "fa",
      timeZone: "Asia/Tehran",
      wellMateFirstValueState: "Completed",
    }).wellMateFirstValueState,
    "Completed",
  );
  assertEquals(
    normalizeProfilePatch({
      version: 2,
      displayName: "Owner",
      locale: "fa",
      timeZone: "Asia/Tehran",
      wellMateFirstValueState: "Skipped",
    }).wellMateFirstValueState,
    "Skipped",
  );
  assertThrows(
    () =>
      normalizeProfilePatch({
        version: 2,
        displayName: "Owner",
        locale: "fa",
        timeZone: "Asia/Tehran",
        wellMateFirstValueState: "CaregiverAuthorized",
      }),
    ApiError,
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
        avatarKey: "person_blue",
      },
      {
        version: 1,
        displayName: "",
        locale: "fa",
        timeZone: "Asia/Tehran",
        avatarKey: "person_blue",
      },
      {
        version: 1,
        displayName: "Owner",
        phoneNumber: "not-a-phone",
        locale: "fa",
        timeZone: "Asia/Tehran",
        avatarKey: "person_blue",
      },
      {
        version: 1,
        displayName: "Owner",
        locale: "persian",
        timeZone: "Asia/Tehran",
        avatarKey: "person_blue",
      },
      {
        version: 1,
        displayName: "Owner",
        locale: "fa",
        timeZone: "Invalid/Zone",
        avatarKey: "person_blue",
      },
      {
        version: 1,
        displayName: "Owner",
        locale: "fa",
        timeZone: "Asia/Tehran",
        avatarKey: "../../private-photo",
      },
    ]
  ) {
    assertThrows(() => normalizeProfilePatch(body), ApiError);
  }
});

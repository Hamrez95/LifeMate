import { assertEquals, assertThrows } from "jsr:@std/assert@1.0.14";
import { normalizeProfilePatch } from "./profile.ts";

const base = {
  version: 3,
  displayName: "کاربر LifeMate",
  phoneNumber: null,
  locale: "fa",
  timeZone: "Asia/Tehran",
  avatarKey: "person_green",
};

Deno.test("ordinary profile edits do not implicitly complete onboarding", () => {
  const patch = normalizeProfilePatch(base);
  assertEquals(patch.presentationIntent, null);
  assertEquals(patch.completeOnboarding, false);
});

Deno.test("minimal onboarding accepts only explicit presentation intents", () => {
  for (const presentationIntent of ["Self", "Caregiving", "Both"]) {
    const patch = normalizeProfilePatch({
      ...base,
      presentationIntent,
      completeOnboarding: true,
    });
    assertEquals(patch.presentationIntent, presentationIntent);
    assertEquals(patch.completeOnboarding, true);
  }
});

Deno.test("completion cannot be written without a presentation intent", () => {
  assertThrows(
    () => normalizeProfilePatch({ ...base, completeOnboarding: true }),
    Error,
    "presentationIntent is required",
  );
});

Deno.test("unknown presentation intent is rejected instead of becoming permission", () => {
  assertThrows(
    () =>
      normalizeProfilePatch({
        ...base,
        presentationIntent: "MedicalAdmin",
        completeOnboarding: true,
      }),
    Error,
    "presentationIntent is not supported",
  );
});

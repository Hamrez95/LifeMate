import { assert, assertEquals } from "jsr:@std/assert@1.0.14";

Deno.test("public care invitation facade cannot invoke an SMS provider", async () => {
  const databaseSource = await Deno.readTextFile(
    new URL("./database.ts", import.meta.url),
  );
  assert(databaseSource.includes("phone_care_invitation_retired"));
  assert(!databaseSource.includes("createPhoneInvitationDeliveryFromEnvironment"));
  assert(!databaseSource.includes("phoneInvitationDelivery.deliver"));
  assert(!databaseSource.includes("createPhoneInvitation:"));
});

Deno.test("care SMS delivery adapter is removed while auth hook stays separate", async () => {
  const deliveryPath = new URL("./phone_invitation_delivery.ts", import.meta.url);
  let deliveryExists = true;
  try {
    await Deno.stat(deliveryPath);
  } catch (error) {
    if (error instanceof Deno.errors.NotFound) deliveryExists = false;
    else throw error;
  }
  assertEquals(deliveryExists, false);

  const hookPath = new URL("../lifemate-kavenegar-sms-hook/index.ts", import.meta.url);
  const hook = await Deno.readTextFile(hookPath);
  assert(hook.length > 0, "Auth OTP Kavenegar hook must remain present");
});

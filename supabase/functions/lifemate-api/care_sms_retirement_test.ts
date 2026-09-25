import { assert, assertFalse } from "jsr:@std/assert@1.0.14";

Deno.test("public phone care invitations stay on the canonical provider-free store", async () => {
  const databaseSource = await Deno.readTextFile(
    new URL("./database.ts", import.meta.url),
  );
  const phoneSource = await Deno.readTextFile(
    new URL("./phone_care_invitation.ts", import.meta.url),
  );

  assert(databaseSource.includes('if (contactType === "phone")'));
  assert(
    databaseSource.includes(
      "phoneInvitations.createPhoneInvitation(identity, body)",
    ),
  );
  assert(phoneSource.includes("if (deliver)"));
  assertFalse(/kavenegar/i.test(phoneSource));
  assertFalse(/send\s*sms|sms\s*send/i.test(phoneSource));
});

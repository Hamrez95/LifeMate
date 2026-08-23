import { assertEquals, assertRejects } from "jsr:@std/assert@1.0.14";
import { createLifeMateDatabase } from "./database.ts";
import { ApiError } from "./validation.ts";

Deno.test("public phone care invitation fails closed before provider or database work", async () => {
  const db = createLifeMateDatabase(
    "postgres://unused:unused@127.0.0.1:1/unused",
    "unit-only-contact-secret-with-32-plus-characters",
  );

  const error = await assertRejects(
    () =>
      db.createInvitation(
        {
          auth: {
            id: "retired-phone-invite-subject",
            email: "retired@example.test",
            phone: "+989121234567",
            userMetadata: {},
          },
          appUserId: "11111111-1111-4111-8111-111111111111",
        },
        {
          contactType: "phone",
          contact: "+989351234567",
          consentVersion: "care-patient-consent-v1",
          confirmConsent: true,
        },
      ),
    ApiError,
  );

  assertEquals(error.status, 410);
  assertEquals(error.code, "phone_care_invitation_retired");
});

import { assert, assertEquals, assertRejects } from "jsr:@std/assert@1.0.14";
import { createPhoneInvitationDelivery } from "./phone_invitation_delivery.ts";
import { ApiError } from "./validation.ts";

Deno.test("phone invite delivery stays fail-closed when disabled", async () => {
  let calls = 0;
  const delivery = createPhoneInvitationDelivery({
    enabled: false,
    apiKey: "testApiKey123",
    template: "lifemate-care",
    fetcher: async () => {
      calls++;
      return new Response("{}", { status: 200 });
    },
  });

  const error = await assertRejects(
    () => delivery.deliver("+989121234567", "1234567890"),
    ApiError,
  );
  assertEquals(error.status, 424);
  assertEquals(error.code, "phone_invitation_delivery_unavailable");
  assertEquals(calls, 0);
});

Deno.test("phone invite delivery sends only minimal Kavenegar template fields", async () => {
  let capturedUrl = "";
  let capturedInit: RequestInit | undefined;
  const delivery = createPhoneInvitationDelivery({
    enabled: true,
    apiKey: "testApiKey123",
    template: "lifemate-care",
    fetcher: async (input, init) => {
      capturedUrl = input.toString();
      capturedInit = init;
      return new Response(
        JSON.stringify({
          return: { status: 200, message: "ok" },
          entries: [{ messageid: 42, status: 5 }],
        }),
        { status: 200, headers: { "content-type": "application/json" } },
      );
    },
  });

  await delivery.deliver("+989121234567", "1234567890");

  assertEquals(capturedInit?.method, "POST");
  assert(!capturedUrl.includes("09121234567"));
  assert(!capturedUrl.includes("1234567890"));
  const form = new URLSearchParams(capturedInit?.body?.toString());
  assertEquals(form.get("receptor"), "09121234567");
  assertEquals(form.get("token"), "1234567890");
  assertEquals(form.get("template"), "lifemate-care");
  assertEquals(form.get("type"), "sms");
  assertEquals([...form.keys()].sort(), [
    "receptor",
    "template",
    "token",
    "type",
  ]);
});

Deno.test("phone invite delivery redacts provider response and request secrets", async () => {
  const delivery = createPhoneInvitationDelivery({
    enabled: true,
    apiKey: "testApiKey123",
    template: "lifemate-care",
    fetcher: async () =>
      new Response(
        JSON.stringify({
          return: {
            status: 424,
            message: "provider leaked 09121234567 1234567890",
          },
        }),
        { status: 424, headers: { "content-type": "application/json" } },
      ),
  });

  const error = await assertRejects(
    () => delivery.deliver("+989121234567", "1234567890"),
    ApiError,
  );
  assertEquals(error.status, 424);
  assertEquals(error.code, "phone_invitation_delivery_unavailable");
  assert(!error.message.includes("09121234567"));
  assert(!error.message.includes("1234567890"));
  assert(!error.message.includes("provider leaked"));
});

Deno.test("phone invite transport uncertainty is generic and privacy-safe", async () => {
  const delivery = createPhoneInvitationDelivery({
    enabled: true,
    apiKey: "testApiKey123",
    template: "lifemate-care",
    fetcher: () =>
      Promise.reject(new Error("network 09121234567 token 1234567890")),
  });

  const error = await assertRejects(
    () => delivery.deliver("+989121234567", "1234567890"),
    ApiError,
  );
  assertEquals(error.status, 424);
  assertEquals(error.code, "phone_invitation_delivery_unavailable");
  assert(!error.message.includes("09121234567"));
  assert(!error.message.includes("1234567890"));
});

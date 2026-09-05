import {
  assertEquals,
  assertRejects,
  assertStringIncludes,
} from "jsr:@std/assert@1.0.14";
import { parsePushRegistration } from "./push_registrations.ts";
import { ApiError } from "./validation.ts";

Deno.test("push registration accepts bounded FCM token metadata", () => {
  assertEquals(
    parsePushRegistration({
      productCode: "wellmate",
      platform: "Android",
      provider: "fcm",
      token: "fcm-token-high-entropy-abcdefghijklmnopqrstuvwxyz0123456789",
    }).provider,
    "fcm",
  );
});

Deno.test("push registration rejects short token", async () => {
  await assertRejects(async () => {
    try {
      parsePushRegistration({
        productCode: "wellmate",
        platform: "Android",
        provider: "fcm",
        token: "short",
      });
    } catch (error) {
      if (error instanceof ApiError) {
        assertEquals(error.code, "push_registration_invalid");
      }
      throw error;
    }
  }, ApiError);
});

Deno.test("push store never persists plaintext token", async () => {
  const source = await Deno.readTextFile(
    new URL("./push_registrations.ts", import.meta.url),
  );
  assertStringIncludes(source, "hashMessagingToken");
  assertStringIncludes(source, "encryptMessagingToken");
  if (source.includes("insert into messaging.push_registrations")) {
    throw new Error(
      "Edge code must use the narrow database function instead of direct token table writes.",
    );
  }
});

Deno.test("authenticated consumer dispatcher wires push registration routes", async () => {
  const source = await Deno.readTextFile(
    new URL("./growth_routes.ts", import.meta.url),
  );
  assertStringIncludes(source, "createPushRegistrationRouteHandler");
  assertStringIncludes(source, "await pushRegistrationRoutes(input)");
  assertStringIncludes(
    source,
    "if (pushRegistrationResponse) return pushRegistrationResponse",
  );
});

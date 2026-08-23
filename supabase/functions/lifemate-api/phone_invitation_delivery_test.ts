import { assert } from "jsr:@std/assert@1.0.14";

Deno.test("care SMS delivery module stays retired", async () => {
  let exists = true;
  try {
    await Deno.stat(new URL("./phone_invitation_delivery.ts", import.meta.url));
  } catch (error) {
    if (error instanceof Deno.errors.NotFound) exists = false;
    else throw error;
  }
  assert(!exists);
});

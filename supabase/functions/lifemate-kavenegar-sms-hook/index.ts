import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createSendSmsHookHandler } from "./handler.ts";

const handler = createSendSmsHookHandler({
  apiKey: Deno.env.get("KAVENEGAR_API_KEY"),
  template: Deno.env.get("KAVENEGAR_VERIFY_TEMPLATE"),
  hookSecrets: Deno.env.get("SEND_SMS_HOOK_SECRETS"),
});

Deno.serve(handler);

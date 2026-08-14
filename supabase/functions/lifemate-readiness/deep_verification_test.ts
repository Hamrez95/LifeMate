import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import postgres from "postgres";
import { verifyDeepReadiness } from "./deep_verification.ts";

const databaseUrl = Deno.env.get("TEST_DATABASE_URL");
if (!databaseUrl) {
  throw new Error("TEST_DATABASE_URL is required.");
}

Deno.test({
  name: "restricted runtime passes comprehensive deployment verification",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
    const sql = postgres(databaseUrl, {
      max: 1,
      idle_timeout: 3,
      connect_timeout: 5,
      prepare: false,
    });
    try {
      await verifyDeepReadiness(sql);
    } finally {
      await sql.end({ timeout: 2 });
    }
  },
});

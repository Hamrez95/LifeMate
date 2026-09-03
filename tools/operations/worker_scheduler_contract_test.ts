import { assert } from "jsr:@std/assert@1.0.14";

const infrastructure = await Deno.readTextFile(
  "supabase/infrastructure/20260904003000_lifemate_worker_scheduler.sql",
);
const worker = await Deno.readTextFile(
  "supabase/functions/lifemate-worker/index.ts",
);
const schedulerAuth = await Deno.readTextFile(
  "supabase/functions/lifemate-worker/scheduler_auth.ts",
);

assert(infrastructure.includes("create extension if not exists pg_net"));
assert(infrastructure.includes("create extension if not exists pg_cron"));
assert(infrastructure.includes("lifemate_worker_scheduler_token"));
assert(infrastructure.includes("integration.verify_worker_scheduler_token"));
assert(infrastructure.includes("cron.schedule("));
assert(infrastructure.includes("'lifemate-outbox-worker'"));
assert(infrastructure.includes("'* * * * *'"));
assert(infrastructure.includes("net.http_post("));
assert(!infrastructure.includes("LIFEMATE_WORKER_TOKEN="));
assert(worker.includes('from "./scheduler_auth.ts"'));
assert(worker.includes("await schedulerTokenAccepted(sql, supplied)"));
assert(schedulerAuth.includes("verify_worker_scheduler_token"));

console.log("LifeMate worker scheduler contract: PASS");

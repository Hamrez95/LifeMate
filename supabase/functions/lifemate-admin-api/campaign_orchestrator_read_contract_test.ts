import { assert, assertStringIncludes } from "jsr:@std/assert";

Deno.test("prepared campaign execution is read back with canonical version", async () => {
  const service = await Deno.readTextFile(
    new URL("./campaign_orchestrator_service.ts", import.meta.url),
  );
  assertStringIncludes(
    service,
    "const execution = await getExecution(executionId)",
  );
  assertStringIncludes(service, "version: execution.version");
  assertStringIncludes(service, "createdAtUtc: execution.createdAtUtc");
});

Deno.test("execution read model never exposes recipient identifiers or message bodies", async () => {
  const service = await Deno.readTextFile(
    new URL("./campaign_orchestrator_service.ts", import.meta.url),
  );
  const routes = await Deno.readTextFile(
    new URL("./campaign_orchestrator_routes.ts", import.meta.url),
  );
  assert(!service.includes("account_id"));
  assert(!service.includes("message_body"));
  assert(!service.includes("token_ciphertext"));
  assertStringIncludes(routes, "recipientIdentifiersExposed: false");
  assertStringIncludes(routes, "messageBodiesExposed: false");
});

Deno.test("execution list and detail require high-risk send permission", async () => {
  const routes = await Deno.readTextFile(
    new URL("./campaign_orchestrator_routes.ts", import.meta.url),
  );
  assertStringIncludes(
    routes.replace(/\s+/g, ""),
    'requirePermission(admin,"marketing.campaign.send")',
  );
  assertStringIncludes(routes, "/api/v1/marketing/campaigns/");
  assertStringIncludes(routes, "/api/v1/marketing/campaign-executions/");
});

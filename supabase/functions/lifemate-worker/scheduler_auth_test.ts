import { assertEquals } from "jsr:@std/assert@1.0.14";
import { schedulerTokenAccepted } from "./scheduler_auth.ts";

function fakeSql(result: boolean) {
  return () => Promise.resolve([{ accepted: result }]);
}

Deno.test("scheduler auth rejects malformed credentials before database lookup", async () => {
  let called = false;
  const sql = () => {
    called = true;
    return Promise.resolve([{ accepted: true }]);
  };
  assertEquals(await schedulerTokenAccepted(sql, "short"), false);
  assertEquals(called, false);
});

Deno.test("scheduler auth accepts only database-verified credentials", async () => {
  const candidate = "a".repeat(64);
  assertEquals(await schedulerTokenAccepted(fakeSql(true), candidate), true);
  assertEquals(await schedulerTokenAccepted(fakeSql(false), candidate), false);
});

Deno.test("scheduler auth fails closed when infrastructure is unavailable", async () => {
  const sql = () => Promise.reject(new Error("verifier_unavailable"));
  assertEquals(await schedulerTokenAccepted(sql, "b".repeat(64)), false);
});

Deno.test("scheduler path is not gated by the optional operator token", async () => {
  const source = await Deno.readTextFile("./index.ts");
  assertEquals(
    source.includes("if (!workerToken || workerToken.length < 32)"),
    false,
  );
  assertEquals(source.includes("workerToken !== undefined"), true);
  assertEquals(
    source.includes("await schedulerTokenAccepted(sql, supplied)"),
    true,
  );
});

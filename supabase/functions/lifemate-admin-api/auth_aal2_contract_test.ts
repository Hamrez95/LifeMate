import { requireAal2 } from "./auth.ts";
import { ApiError } from "./validation.ts";

Deno.test("AAL2 is required for every Admin principal including Founder bootstrap subject", () => {
  const aal1Principal = {
    providerSubject: "11111111-1111-4111-8111-111111111111",
    email: null,
    aal: "aal1" as const,
  };

  let thrown: unknown = null;
  try {
    requireAal2(aal1Principal);
  } catch (error) {
    thrown = error;
  }

  if (!(thrown instanceof ApiError)) throw new Error("AAL1 must fail with ApiError");
  if (thrown.status !== 403 || thrown.code !== "mfa_required") {
    throw new Error(`unexpected AAL1 denial: ${thrown.status}/${thrown.code}`);
  }

  requireAal2({ ...aal1Principal, aal: "aal2" });
});

Deno.test("Admin API auth source has no configured-subject MFA bypass", async () => {
  const source = await Deno.readTextFile(new URL("./auth.ts", import.meta.url));
  for (const forbidden of [
    "temporaryFounderSubject",
    "LIFEMATE_ADMIN_BOOTSTRAP_AUTH_SUBJECT",
    "founder-only compatibility",
  ]) {
    if (source.includes(forbidden)) throw new Error(`forbidden AAL2 bypass remains: ${forbidden}`);
  }
});

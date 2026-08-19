import { readFileSync } from "node:fs";

const files = {
  crypto: "supabase/functions/_shared/provider_identity_handle_crypto.ts",
  bridge: "supabase/functions/lifemate-api/identity_bridge.ts",
  worker: "supabase/functions/lifemate-worker/provider_auth_subject.ts",
  rotation: "tools/security/provider-handle-key-rotation.ts",
  readiness: "tools/security/provider-handle-key-rotation-readiness.ts",
  rotationWorkflow: ".github/workflows/provider-handle-key-rotation.yml",
  readinessWorkflow:
    ".github/workflows/provider-handle-key-rotation-readiness.yml",
};

const source = Object.fromEntries(
  Object.entries(files).map(([name, path]) => [
    name,
    readFileSync(path, "utf8"),
  ]),
);

function requireText(text, marker, message) {
  if (!text.includes(marker)) throw new Error(message);
}

function forbid(text, pattern, message) {
  if (pattern.test(text)) throw new Error(message);
}

for (const marker of [
  "LIFEMATE_IDENTITY_PROVIDER_HANDLE_PREVIOUS_KEY",
  "LIFEMATE_IDENTITY_PROVIDER_HANDLE_PREVIOUS_KEY_VERSION",
  "readProviderIdentityHandleKeySet",
  "Previous provider identity-handle key version must differ",
]) {
  requireText(
    source.crypto,
    marker,
    `Provider-handle keyset contract is missing ${marker}.`,
  );
}

requireText(
  source.bridge,
  "readProviderIdentityHandleKey",
  "Identity bridge must continue to use the active provider-handle key contract.",
);
if (source.bridge.includes("readProviderIdentityHandleKeySet")) {
  throw new Error(
    "Identity bridge writer must not select the previous provider-handle key.",
  );
}

for (const marker of [
  "readProviderIdentityHandleKeySet",
  "providerHandleKeys.active",
  "providerHandleKeys.previous",
  "provider_handle_decrypt_failed",
]) {
  requireText(
    source.worker,
    marker,
    `Worker provider-handle overlap contract is missing ${marker}.`,
  );
}

for (const marker of [
  "provider='supabase_auth'",
  "issuer='supabase'",
  "status='Active'",
  "ROTATE-PROVIDER-HANDLES",
  "ciphertext_b64=${entry.row.ciphertext_b64}",
  "nonce_b64=${entry.row.nonce_b64}",
  "key_version=${Number(entry.row.key_version)}",
]) {
  requireText(
    source.rotation,
    marker,
    `Provider-handle rotation safety contract is missing ${marker}.`,
  );
}
const updateSetMatch = source.rotation.match(
  /update identity\.provider_identity_handles\s+set([\s\S]*?)\s+where\s/i,
);
if (!updateSetMatch) {
  throw new Error(
    "Provider-handle rotation must contain the reviewed canonical envelope update.",
  );
}
forbid(
  updateSetMatch[1],
  /\b(account_id|provider|issuer|status)\s*=/i,
  "Provider-handle rotation must not rewrite ownership/provider/issuer/status.",
);
for (const marker of [
  "ciphertext_b64=",
  "nonce_b64=",
  "key_version=",
  "updated_at_utc=",
]) {
  requireText(
    updateSetMatch[1],
    marker,
    `Provider-handle rotation SET clause is missing ${marker}.`,
  );
}

for (const marker of [
  "currentHandles > 0",
  "activeVersionReadyHandles === currentHandles",
  "previousVersionHandles === 0",
  "unknownVersionHandles === 0",
  "invalidEnvelopeHandles === 0",
]) {
  requireText(
    source.readiness,
    marker,
    `Provider-handle readiness contract is missing ${marker}.`,
  );
}
forbid(
  source.readiness,
  /\b(insert\s+into|update|delete\s+from)\s+identity\.provider_identity_handles/i,
  "Provider-handle readiness must remain read-only.",
);
forbid(
  source.readiness,
  /decryptProviderIdentitySubject|encryptProviderIdentitySubject|PROVIDER_HANDLE_KEY(?!_VERSION)/,
  "Provider-handle readiness must not require encryption key material.",
);

for (const [name, workflow] of [
  ["rotation", source.rotationWorkflow],
  ["readiness", source.readinessWorkflow],
]) {
  requireText(workflow, "workflow_dispatch:", `${name} workflow must be manual.`);
  forbid(
    workflow,
    /^[ \t]+(pull_request|push|schedule):/m,
    `${name} workflow must not run automatically.`,
  );
  requireText(workflow, "environment: beta", `${name} workflow must use beta.`);
  requireText(
    workflow,
    `test "$GITHUB_REF" = 'refs/heads/main'`,
    `${name} workflow must require exact main.`,
  );
  requireText(
    workflow,
    `github.event.repository.private }}\" = 'true'`,
    `${name} workflow must require a private repository.`,
  );
  requireText(
    workflow,
    `github.ref_protected }}\" = 'true'`,
    `${name} workflow must require branch protection.`,
  );
  if (workflow.includes("upload-artifact")) {
    throw new Error(`${name} workflow must not upload provider-handle artifacts.`);
  }
}

for (const marker of [
  "LIFEMATE_IDENTITY_PROVIDER_HANDLE_KEY:",
  "LIFEMATE_IDENTITY_PROVIDER_HANDLE_PREVIOUS_KEY:",
  "ROTATE-PROVIDER-HANDLES",
  "provider-handle-key-rotation.ts",
]) {
  requireText(
    source.rotationWorkflow,
    marker,
    `Provider-handle rotation workflow is missing ${marker}.`,
  );
}

for (const forbiddenSecret of [
  "secrets.LIFEMATE_IDENTITY_PROVIDER_HANDLE_KEY }}",
  "secrets.LIFEMATE_IDENTITY_PROVIDER_HANDLE_PREVIOUS_KEY }}",
]) {
  if (source.readinessWorkflow.includes(forbiddenSecret)) {
    throw new Error(
      "Provider-handle readiness workflow must not receive encryption key secrets.",
    );
  }
}
for (const marker of [
  "LIFEMATE_IDENTITY_PROVIDER_HANDLE_KEY_VERSION:",
  "LIFEMATE_IDENTITY_PROVIDER_HANDLE_PREVIOUS_KEY_VERSION:",
  "provider-handle-key-rotation-readiness.ts",
  "readyForPreviousKeyRemoval",
]) {
  requireText(
    source.readinessWorkflow,
    marker,
    `Provider-handle readiness workflow is missing ${marker}.`,
  );
}

console.log("Provider-handle key rotation policy verified.");

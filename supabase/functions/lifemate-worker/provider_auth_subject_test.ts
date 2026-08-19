import {
  assertEquals,
  assertRejects,
  assertThrows,
} from "jsr:@std/assert@1.0.14";
import {
  encryptProviderIdentitySubject,
  type ProviderIdentityHandleEnvelope,
} from "../_shared/provider_identity_handle_crypto.ts";
import { createProviderAuthSubjectResolver } from "./provider_auth_subject.ts";

const accountId = "91000000-0000-4000-8000-000000000001";
const otherAccountId = "91000000-0000-4000-8000-000000000002";
const subject = "92000000-0000-4000-8000-000000000001";
const key = "worker-provider-handle-test-key-32-bytes-minimum";
const keyVersion = 4;
const previousKey = "worker-provider-handle-previous-key-32-bytes-minimum";
const previousKeyVersion = 3;

function environment(overrides: Record<string, string> = {}) {
  const values: Record<string, string> = {
    LIFEMATE_IDENTITY_PROVIDER_HANDLE_DUAL_WRITE: "true",
    LIFEMATE_IDENTITY_PROVIDER_HANDLE_KEY: key,
    LIFEMATE_IDENTITY_PROVIDER_HANDLE_KEY_VERSION: String(keyVersion),
    LIFEMATE_IDENTITY_LINK_RAW_RETIREMENT: "false",
    ...overrides,
  };
  return (name: string) => values[name];
}

async function encryptedRow(
  boundAccountId = accountId,
  encryptionKey = key,
  encryptionKeyVersion = keyVersion,
): Promise<{
  ciphertext_b64: string;
  nonce_b64: string;
  key_version: number;
}> {
  const envelope: ProviderIdentityHandleEnvelope =
    await encryptProviderIdentitySubject(
      { secret: encryptionKey, keyVersion: encryptionKeyVersion },
      {
        accountId: boundAccountId,
        provider: "supabase_auth",
        issuer: "supabase",
      },
      subject,
      new Uint8Array(12).fill(7),
    );
  return {
    ciphertext_b64: envelope.ciphertextB64,
    nonce_b64: envelope.nonceB64,
    key_version: envelope.keyVersion,
  };
}

Deno.test("Worker recovers Supabase Auth UUID from encrypted handle", async () => {
  let legacyCalls = 0;
  const row = await encryptedRow();
  const resolver = createProviderAuthSubjectResolver(null, {
    readEnvironment: environment(),
    lookupHandle: async () => [row],
    lookupLegacy: async () => {
      legacyCalls += 1;
      return [{ auth_subject: subject }];
    },
  });
  assertEquals(await resolver.resolve(accountId), subject);
  assertEquals(legacyCalls, 0);
});

Deno.test("Worker recovers a previous-version handle during bounded overlap", async () => {
  let legacyCalls = 0;
  const row = await encryptedRow(accountId, previousKey, previousKeyVersion);
  const resolver = createProviderAuthSubjectResolver(null, {
    readEnvironment: environment({
      LIFEMATE_IDENTITY_PROVIDER_HANDLE_PREVIOUS_KEY: previousKey,
      LIFEMATE_IDENTITY_PROVIDER_HANDLE_PREVIOUS_KEY_VERSION: String(
        previousKeyVersion,
      ),
      LIFEMATE_IDENTITY_LINK_RAW_RETIREMENT: "true",
    }),
    lookupHandle: async () => [row],
    lookupLegacy: async () => {
      legacyCalls += 1;
      return [{ auth_subject: subject }];
    },
  });
  assertEquals(await resolver.resolve(accountId), subject);
  assertEquals(legacyCalls, 0);
});

Deno.test("unknown handle key version fails closed during overlap", async () => {
  let legacyCalls = 0;
  const row = await encryptedRow();
  row.key_version = keyVersion + 1;
  const resolver = createProviderAuthSubjectResolver(null, {
    readEnvironment: environment({
      LIFEMATE_IDENTITY_PROVIDER_HANDLE_PREVIOUS_KEY: previousKey,
      LIFEMATE_IDENTITY_PROVIDER_HANDLE_PREVIOUS_KEY_VERSION: String(
        previousKeyVersion,
      ),
      LIFEMATE_IDENTITY_LINK_RAW_RETIREMENT: "true",
    }),
    lookupHandle: async () => [row],
    lookupLegacy: async () => {
      legacyCalls += 1;
      return [{ auth_subject: subject }];
    },
  });
  await assertRejects(
    () => resolver.resolve(accountId),
    Error,
    "provider_handle_decrypt_failed",
  );
  assertEquals(legacyCalls, 0);
});

Deno.test("authenticated envelope is bound to Account AAD", async () => {
  let legacyCalls = 0;
  const row = await encryptedRow(otherAccountId);
  const resolver = createProviderAuthSubjectResolver(null, {
    readEnvironment: environment(),
    lookupHandle: async () => [row],
    lookupLegacy: async () => {
      legacyCalls += 1;
      return [{ auth_subject: subject }];
    },
  });
  await assertRejects(
    () => resolver.resolve(accountId),
    Error,
    "provider_handle_decrypt_failed",
  );
  assertEquals(legacyCalls, 0);
});

Deno.test("wrong external key fails closed without raw fallback", async () => {
  let legacyCalls = 0;
  const row = await encryptedRow();
  const resolver = createProviderAuthSubjectResolver(null, {
    readEnvironment: environment({
      LIFEMATE_IDENTITY_PROVIDER_HANDLE_KEY:
        "different-worker-provider-handle-key-32-bytes-minimum",
    }),
    lookupHandle: async () => [row],
    lookupLegacy: async () => {
      legacyCalls += 1;
      return [{ auth_subject: subject }];
    },
  });
  await assertRejects(
    () => resolver.resolve(accountId),
    Error,
    "provider_handle_decrypt_failed",
  );
  assertEquals(legacyCalls, 0);
});

Deno.test("missing handle keeps bounded raw fallback before retirement", async () => {
  let legacyCalls = 0;
  const resolver = createProviderAuthSubjectResolver(null, {
    readEnvironment: environment(),
    lookupHandle: async () => [],
    lookupLegacy: async () => {
      legacyCalls += 1;
      return [{ auth_subject: subject }];
    },
  });
  assertEquals(await resolver.resolve(accountId), subject);
  assertEquals(legacyCalls, 1);
});

Deno.test("raw retirement refuses a missing encrypted provider handle", async () => {
  let legacyCalls = 0;
  const resolver = createProviderAuthSubjectResolver(null, {
    readEnvironment: environment({
      LIFEMATE_IDENTITY_LINK_RAW_RETIREMENT: "true",
    }),
    lookupHandle: async () => [],
    lookupLegacy: async () => {
      legacyCalls += 1;
      return [{ auth_subject: subject }];
    },
  });
  await assertRejects(
    () => resolver.resolve(accountId),
    Error,
    "provider_handle_missing",
  );
  assertEquals(legacyCalls, 0);
});

Deno.test("raw retirement requires provider-handle dual-write", () => {
  assertThrows(
    () =>
      createProviderAuthSubjectResolver(null, {
        readEnvironment: environment({
          LIFEMATE_IDENTITY_PROVIDER_HANDLE_DUAL_WRITE: "false",
          LIFEMATE_IDENTITY_LINK_RAW_RETIREMENT: "true",
        }),
        lookupHandle: async () => [],
        lookupLegacy: async () => [],
      }),
    Error,
    "LIFEMATE_IDENTITY_PROVIDER_HANDLE_DUAL_WRITE=true",
  );
});

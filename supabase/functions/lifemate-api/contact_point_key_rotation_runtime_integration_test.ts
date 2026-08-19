import { assertEquals, assertRejects } from "jsr:@std/assert@1.0.14";
import postgres from "postgres";
import { createContactPointWriter } from "./contact_points.ts";
import { createDataExportStore } from "./data_export.ts";
import { type AuthUser, createLifeMateDatabase } from "./database.ts";
import { createProfileStore } from "./profile.ts";
import { ApiError } from "./validation.ts";

const databaseUrl = Deno.env.get("TEST_DATABASE_URL");
if (!databaseUrl) {
  throw new Error(
    "TEST_DATABASE_URL is required for ContactPoint key-rotation runtime integration tests.",
  );
}

const envNames = [
  "LIFEMATE_PROFILE_CONTACT_LOOKUP_MODE",
  "LIFEMATE_IDENTITY_CONTACT_ENCRYPTION_KEY",
  "LIFEMATE_IDENTITY_CONTACT_ENCRYPTION_KEY_VERSION",
  "LIFEMATE_IDENTITY_CONTACT_PREVIOUS_ENCRYPTION_KEY",
  "LIFEMATE_IDENTITY_CONTACT_PREVIOUS_ENCRYPTION_KEY_VERSION",
  "LIFEMATE_IDENTITY_CONTACT_READINESS_APPROVED",
  "LIFEMATE_IDENTITY_CONTACT_RAW_RETIREMENT",
  "LIFEMATE_IDENTITY_CONTACT_DUAL_WRITE",
] as const;

type ScenarioPhase = "read" | "write" | "unknown";

Deno.test({
  name: "previous envelope key keeps contact-only Profile and export readable",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: () => runScenario("read"),
});

Deno.test({
  name: "overlap writes re-encrypt current contacts with the active key only",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: () => runScenario("write"),
});

Deno.test({
  name:
    "unknown ContactPoint envelope version fails closed after raw retirement",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: () => runScenario("unknown"),
});

async function runScenario(phase: ScenarioPhase): Promise<void> {
  const admin = postgres(databaseUrl!, { max: 1, prepare: false });
  const previousEnvironment = new Map<string, string | undefined>();
  for (const name of envNames) {
    previousEnvironment.set(name, Deno.env.get(name));
  }

  const hashingSecret =
    "contact-key-rotation-runtime-hash-secret-32-bytes-minimum";
  const previousKey = {
    secret: "contact-key-rotation-runtime-previous-key-32-bytes-minimum",
    keyVersion: 81,
  };
  const activeKey = {
    secret: "contact-key-rotation-runtime-active-key-32-bytes-minimum",
    keyVersion: 82,
  };
  const suffix = crypto.randomUUID();
  const auth: AuthUser = {
    id: `contact-key-rotation-runtime-${suffix}`,
    email: `Rotation-${suffix}@Example.Test`,
    phone: null,
    userMetadata: {},
  };
  const initialPhone = "+989121234567";
  const updatedPhone = "+989120001122";
  let appUserId: string | null = null;
  let accountId: string | null = null;

  try {
    configureLegacyBootstrap();
    const db = createLifeMateDatabase(databaseUrl!, hashingSecret);
    await db.bootstrapUser(auth, {
      displayName: "Contact Key Rotation",
      locale: "fa",
      timeZone: "Asia/Tehran",
    });
    const identity = await db.requireIdentity(auth);
    appUserId = identity.appUserId;
    accountId = await accountFor(admin, appUserId);

    const previousWriter = createContactPointWriter(hashingSecret, {
      enabled: true,
      encryptionKey: previousKey,
    });
    await admin.begin(async (tx) => {
      await previousWriter.syncForAccount(
        tx,
        accountId!,
        { email: auth.email, phone: initialPhone },
        "replace",
      );
    });
    await admin`
      update lifemate.user_profiles
      set email=null,phone_number=null,updated_at_utc=now()
      where user_id=${appUserId}::uuid
    `;

    const previousRows = await admin`
      select kind,encryption_key_version
      from identity.contact_points
      where account_id=${accountId}::uuid and status <> 'Revoked'
      order by kind
    `;
    assertEquals(previousRows.length, 2);
    assertEquals(
      previousRows.every((row) =>
        Number(row.encryption_key_version) === previousKey.keyVersion
      ),
      true,
    );

    configureOverlap(activeKey, previousKey);
    const profileStore = createProfileStore(databaseUrl!, hashingSecret);
    const profile = await profileStore.getProfile(appUserId);
    assertEquals(profile.email, String(auth.email).toLowerCase());
    assertEquals(profile.phoneNumber, initialPhone);

    const exported = await createDataExportStore(databaseUrl!)
      .exportAccountData(appUserId);
    const exportedProfile = exported.profile as Record<string, unknown>;
    assertEquals(exportedProfile.email, String(auth.email).toLowerCase());
    assertEquals(exportedProfile.phoneNumber, initialPhone);
    if (phase === "read") return;

    const updated = await profileStore.updateProfile(appUserId, auth, {
      version: profile.version,
      displayName: "Contact Key Rotation Updated",
      phoneNumber: updatedPhone,
      locale: "fa",
      timeZone: "Asia/Tehran",
      avatarKey: "person_green",
    });
    assertEquals(updated.email, String(auth.email).toLowerCase());
    assertEquals(updated.phoneNumber, updatedPhone);

    const activeRows = await admin`
      select kind,encryption_key_version
      from identity.contact_points
      where account_id=${accountId}::uuid and status <> 'Revoked'
      order by kind
    `;
    assertEquals(activeRows.length, 2);
    assertEquals(
      activeRows.every((row) =>
        Number(row.encryption_key_version) === activeKey.keyVersion
      ),
      true,
    );
    await assertRawContactsNull(admin, appUserId);
    if (phase === "write") return;

    await admin`
      update identity.contact_points
      set encryption_key_version=${activeKey.keyVersion + 1}
      where account_id=${accountId}::uuid
        and kind='Phone' and status <> 'Revoked'
    `;
    const unavailable = await assertRejects(
      () => profileStore.getProfile(appUserId!),
      ApiError,
    );
    assertEquals(unavailable.status, 503);
    assertEquals(unavailable.code, "contact_point_unavailable");
  } finally {
    await cleanup(admin, appUserId, accountId);
    for (const name of envNames) {
      const value = previousEnvironment.get(name);
      if (value === undefined) Deno.env.delete(name);
      else Deno.env.set(name, value);
    }
    await admin.end({ timeout: 5 });
  }
}

function configureLegacyBootstrap(): void {
  Deno.env.set("LIFEMATE_PROFILE_CONTACT_LOOKUP_MODE", "legacy");
  Deno.env.set("LIFEMATE_IDENTITY_CONTACT_DUAL_WRITE", "false");
  Deno.env.set("LIFEMATE_IDENTITY_CONTACT_RAW_RETIREMENT", "false");
  Deno.env.set("LIFEMATE_IDENTITY_CONTACT_READINESS_APPROVED", "false");
  for (
    const name of [
      "LIFEMATE_IDENTITY_CONTACT_ENCRYPTION_KEY",
      "LIFEMATE_IDENTITY_CONTACT_ENCRYPTION_KEY_VERSION",
      "LIFEMATE_IDENTITY_CONTACT_PREVIOUS_ENCRYPTION_KEY",
      "LIFEMATE_IDENTITY_CONTACT_PREVIOUS_ENCRYPTION_KEY_VERSION",
    ]
  ) {
    Deno.env.delete(name);
  }
}

function configureOverlap(
  activeKey: { secret: string; keyVersion: number },
  previousKey: { secret: string; keyVersion: number },
): void {
  Deno.env.set("LIFEMATE_PROFILE_CONTACT_LOOKUP_MODE", "contact-only");
  Deno.env.set("LIFEMATE_IDENTITY_CONTACT_READINESS_APPROVED", "true");
  Deno.env.set("LIFEMATE_IDENTITY_CONTACT_DUAL_WRITE", "true");
  Deno.env.set("LIFEMATE_IDENTITY_CONTACT_RAW_RETIREMENT", "true");
  Deno.env.set("LIFEMATE_IDENTITY_CONTACT_ENCRYPTION_KEY", activeKey.secret);
  Deno.env.set(
    "LIFEMATE_IDENTITY_CONTACT_ENCRYPTION_KEY_VERSION",
    String(activeKey.keyVersion),
  );
  Deno.env.set(
    "LIFEMATE_IDENTITY_CONTACT_PREVIOUS_ENCRYPTION_KEY",
    previousKey.secret,
  );
  Deno.env.set(
    "LIFEMATE_IDENTITY_CONTACT_PREVIOUS_ENCRYPTION_KEY_VERSION",
    String(previousKey.keyVersion),
  );
}

async function accountFor(connection: any, appUserId: string): Promise<string> {
  const rows = await connection`
    select identity.account_id_for_legacy_app_user(${appUserId}::uuid)::text
      as account_id
  `;
  const accountId = rows[0]?.account_id;
  if (typeof accountId !== "string" || accountId.length === 0) {
    throw new Error(
      "Expected Account mapping for ContactPoint rotation runtime test.",
    );
  }
  return accountId;
}

async function assertRawContactsNull(
  connection: any,
  appUserId: string,
): Promise<void> {
  const rows = await connection`
    select email,phone_number
    from lifemate.user_profiles
    where user_id=${appUserId}::uuid
  `;
  assertEquals(rows.length, 1);
  assertEquals(rows[0].email, null);
  assertEquals(rows[0].phone_number, null);
}

async function cleanup(
  connection: any,
  appUserId: string | null,
  accountId: string | null,
): Promise<void> {
  if (accountId) {
    await connection`
      delete from identity.contact_points where account_id=${accountId}::uuid
    `.catch(() => undefined);
  }
  if (!appUserId) return;
  await connection`
    delete from lifemate.audit_logs
    where actor_user_id=${appUserId}::uuid or resource_id=${appUserId}::uuid
  `.catch(() => undefined);
  await connection`
    delete from lifemate.user_profiles where user_id=${appUserId}::uuid
  `.catch(() => undefined);
  if (accountId) {
    await connection`
      delete from identity.external_identity_tokens where account_id=${accountId}::uuid
    `.catch(() => undefined);
    await connection`
      delete from identity.external_identities where account_id=${accountId}::uuid
    `.catch(() => undefined);
    await connection`
      delete from core.account_person_links where account_id=${accountId}::uuid
    `.catch(() => undefined);
    await connection`
      delete from ecosystem.app_enrollments where account_id=${accountId}::uuid
    `.catch(() => undefined);
    await connection`
      delete from identity.accounts where id=${accountId}::uuid
    `.catch(() => undefined);
  }
  await connection`
    delete from lifemate.app_users where id=${appUserId}::uuid
  `.catch(() => undefined);
  await connection`
    delete from core.person_profiles where person_id=${appUserId}::uuid
  `.catch(() => undefined);
  await connection`
    delete from core.persons where id=${appUserId}::uuid
  `.catch(() => undefined);
}

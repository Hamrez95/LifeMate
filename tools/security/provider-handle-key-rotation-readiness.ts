import postgres from "npm:postgres@3.4.7";

export type ProviderHandleKeyRotationReadiness = {
  activeVersion: number;
  previousVersion: number;
  currentHandles: number;
  activeVersionReadyHandles: number;
  previousVersionHandles: number;
  unknownVersionHandles: number;
  invalidEnvelopeHandles: number;
  readyForPreviousKeyRemoval: boolean;
};

function requireVersion(name: string, value: number): number {
  if (!Number.isSafeInteger(value) || value < 1 || value > 32767) {
    throw new Error(`${name} must be an integer from 1 to 32767.`);
  }
  return value;
}

export async function assessProviderHandleKeyRotationReadiness(options: {
  databaseUrl: string;
  activeVersion: number;
  previousVersion: number;
}): Promise<ProviderHandleKeyRotationReadiness> {
  const databaseUrl = options.databaseUrl.trim();
  if (!databaseUrl) throw new Error("Database URL is required.");
  const activeVersion = requireVersion(
    "Active key version",
    options.activeVersion,
  );
  const previousVersion = requireVersion(
    "Previous key version",
    options.previousVersion,
  );
  if (activeVersion === previousVersion) {
    throw new Error("Active and previous key versions must differ.");
  }

  const sql = postgres(databaseUrl, {
    max: 1,
    prepare: false,
    idle_timeout: 5,
    connect_timeout: 5,
  });
  try {
    const rows = await sql`
      select
        count(*)::int as current_handles,
        count(*) filter (
          where key_version=${activeVersion}
            and length(ciphertext_b64) between 24 and 5500
            and length(nonce_b64) between 16 and 32
        )::int as active_ready,
        count(*) filter (
          where key_version=${previousVersion}
            and length(ciphertext_b64) between 24 and 5500
            and length(nonce_b64) between 16 and 32
        )::int as previous_version,
        count(*) filter (
          where key_version not in (${activeVersion},${previousVersion})
        )::int as unknown_version,
        count(*) filter (
          where length(ciphertext_b64) not between 24 and 5500
             or length(nonce_b64) not between 16 and 32
        )::int as invalid_envelope
      from identity.provider_identity_handles
      where provider='supabase_auth'
        and issuer='supabase'
        and status='Active'
    `;
    const row = rows[0] ?? {};
    const currentHandles = Number(row.current_handles ?? 0);
    const activeVersionReadyHandles = Number(row.active_ready ?? 0);
    const previousVersionHandles = Number(row.previous_version ?? 0);
    const unknownVersionHandles = Number(row.unknown_version ?? 0);
    const invalidEnvelopeHandles = Number(row.invalid_envelope ?? 0);
    const readyForPreviousKeyRemoval = currentHandles > 0 &&
      activeVersionReadyHandles === currentHandles &&
      previousVersionHandles === 0 &&
      unknownVersionHandles === 0 &&
      invalidEnvelopeHandles === 0;
    return {
      activeVersion,
      previousVersion,
      currentHandles,
      activeVersionReadyHandles,
      previousVersionHandles,
      unknownVersionHandles,
      invalidEnvelopeHandles,
      readyForPreviousKeyRemoval,
    };
  } finally {
    await sql.end({ timeout: 2 });
  }
}

if (import.meta.main) {
  const summary = await assessProviderHandleKeyRotationReadiness({
    databaseUrl: Deno.env.get("LIFEMATE_IDENTITY_MIGRATION_DATABASE_URL") ?? "",
    activeVersion: Number(
      Deno.env.get("LIFEMATE_IDENTITY_PROVIDER_HANDLE_KEY_VERSION") ?? "",
    ),
    previousVersion: Number(
      Deno.env.get("LIFEMATE_IDENTITY_PROVIDER_HANDLE_PREVIOUS_KEY_VERSION") ??
        "",
    ),
  });
  console.log(JSON.stringify(summary));
  if (!summary.readyForPreviousKeyRemoval) Deno.exit(2);
}

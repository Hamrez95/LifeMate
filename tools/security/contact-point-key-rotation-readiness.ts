import postgres from "npm:postgres@3.4.7";

export type ContactPointKeyRotationReadiness = {
  activeVersion: number;
  previousVersion: number;
  currentContacts: number;
  activeVersionReadyContacts: number;
  previousVersionContacts: number;
  unknownVersionContacts: number;
  invalidEnvelopeContacts: number;
  readyForPreviousKeyRemoval: boolean;
};

function requireKeyVersion(name: string, value: number): number {
  if (!Number.isSafeInteger(value) || value < 1 || value > 32767) {
    throw new Error(`${name} must be an integer from 1 to 32767.`);
  }
  return value;
}

export async function assessContactPointKeyRotationReadiness(options: {
  databaseUrl: string;
  activeVersion: number;
  previousVersion: number;
}): Promise<ContactPointKeyRotationReadiness> {
  const databaseUrl = options.databaseUrl.trim();
  if (!databaseUrl) throw new Error("Database URL is required.");
  const activeVersion = requireKeyVersion(
    "Active ContactPoint encryption key version",
    options.activeVersion,
  );
  const previousVersion = requireKeyVersion(
    "Previous ContactPoint encryption key version",
    options.previousVersion,
  );
  if (activeVersion === previousVersion) {
    throw new Error(
      "Active and previous ContactPoint encryption key versions must differ.",
    );
  }

  const sql = postgres(databaseUrl, {
    max: 1,
    prepare: false,
    idle_timeout: 5,
    connect_timeout: 5,
  });
  try {
    const rows = await sql<{
      current_contacts: number;
      active_version_ready_contacts: number;
      previous_version_contacts: number;
      unknown_version_contacts: number;
      invalid_envelope_contacts: number;
    }[]>`
      select
        count(*)::int as current_contacts,
        count(*) filter (
          where encrypted_value is not null
            and encryption_nonce_b64 is not null
            and encryption_key_version=${activeVersion}
        )::int as active_version_ready_contacts,
        count(*) filter (
          where encrypted_value is not null
            and encryption_nonce_b64 is not null
            and encryption_key_version=${previousVersion}
        )::int as previous_version_contacts,
        count(*) filter (
          where encryption_key_version is not null
            and encryption_key_version not in (${activeVersion},${previousVersion})
        )::int as unknown_version_contacts,
        count(*) filter (
          where encrypted_value is null
             or encryption_nonce_b64 is null
             or encryption_key_version is null
             or length(encryption_nonce_b64) < 16
             or length(encryption_nonce_b64) > 32
        )::int as invalid_envelope_contacts
      from identity.contact_points
      where status <> 'Revoked'
    `;
    const row = rows[0] ?? {
      current_contacts: 0,
      active_version_ready_contacts: 0,
      previous_version_contacts: 0,
      unknown_version_contacts: 0,
      invalid_envelope_contacts: 0,
    };
    const currentContacts = Number(row.current_contacts);
    const activeVersionReadyContacts = Number(
      row.active_version_ready_contacts,
    );
    const previousVersionContacts = Number(row.previous_version_contacts);
    const unknownVersionContacts = Number(row.unknown_version_contacts);
    const invalidEnvelopeContacts = Number(row.invalid_envelope_contacts);

    return {
      activeVersion,
      previousVersion,
      currentContacts,
      activeVersionReadyContacts,
      previousVersionContacts,
      unknownVersionContacts,
      invalidEnvelopeContacts,
      readyForPreviousKeyRemoval: currentContacts > 0 &&
        activeVersionReadyContacts === currentContacts &&
        previousVersionContacts === 0 &&
        unknownVersionContacts === 0 &&
        invalidEnvelopeContacts === 0,
    };
  } finally {
    await sql.end({ timeout: 2 });
  }
}

if (import.meta.main) {
  const result = await assessContactPointKeyRotationReadiness({
    databaseUrl: Deno.env.get("LIFEMATE_CONTACT_MIGRATION_DATABASE_URL") ?? "",
    activeVersion: Number(
      Deno.env.get("LIFEMATE_IDENTITY_CONTACT_ENCRYPTION_KEY_VERSION") ?? "",
    ),
    previousVersion: Number(
      Deno.env.get(
        "LIFEMATE_IDENTITY_CONTACT_PREVIOUS_ENCRYPTION_KEY_VERSION",
      ) ?? "",
    ),
  });
  // Counts and key-version numbers only. Plaintext, hashes, ciphertext, nonces,
  // database URLs and key material are intentionally omitted.
  console.log(JSON.stringify(result));
  if (!result.readyForPreviousKeyRemoval) Deno.exit(2);
}

import { getLifeMateSql } from "./database_client.ts";
import { ApiError } from "./validation.ts";

export type CocoonCanonicalIdentity = {
  accountId: string;
  personId: string;
};

export function createCocoonIdentityResolver(databaseUrl: string) {
  const sql = getLifeMateSql(databaseUrl);

  async function resolve(appUserId: string): Promise<CocoonCanonicalIdentity> {
    const rows = await sql`
      select
        identity.account_id_for_legacy_app_user(${appUserId}::uuid)::text
          as account_id,
        core.self_person_id_for_legacy_app_user(${appUserId}::uuid)::text
          as person_id
    `;
    const accountId = rows[0]?.account_id == null
      ? null
      : String(rows[0].account_id);
    const personId = rows[0]?.person_id == null
      ? null
      : String(rows[0].person_id);
    if (!accountId || !personId) {
      throw new ApiError(
        409,
        "cocoon_person_context_missing",
        "Cocoon person context is not ready.",
      );
    }
    return { accountId, personId };
  }

  return { resolve };
}

import { getLifeMateSql } from "./database_client.ts";
import { ApiError } from "./validation.ts";

type Row = Record<string, unknown>;

export type CapabilitySnapshot = {
  accountId: string;
  selfPersonId: string | null;
  applications: string[];
  features: string[];
};

export function createAuthorizationStore(databaseUrl: string) {
  const sql = getLifeMateSql(databaseUrl);

  async function requirePersonFeature(
    accountId: string,
    personId: string,
    scope: string,
    featureCode: string,
    consentPurpose = "care_sharing",
  ): Promise<void> {
    const rows = await sql`
      select security.can_access_person_feature(
        ${accountId}::uuid,
        ${personId}::uuid,
        ${scope}::character varying,
        ${featureCode}::character varying,
        ${consentPurpose}::character varying,
        now()
      ) as allowed
    `;
    if (rows[0]?.allowed !== true) {
      throw new ApiError(
        403,
        "person_access_denied",
        "Access to this person's data is not permitted.",
      );
    }
  }

  async function capabilitySnapshot(accountId: string): Promise<CapabilitySnapshot> {
    const accountRows = await sql`
      select a.id,
        (
          select l.person_id
          from core.account_person_links l
          where l.account_id=a.id
            and l.link_type='Self'
            and l.status='Active'
          order by l.created_at_utc, l.person_id
          limit 1
        ) as self_person_id
      from identity.accounts a
      where a.id=${accountId}::uuid and a.status='Active'
      limit 1
    `;
    const account = accountRows[0] as Row | undefined;
    if (!account) {
      throw new ApiError(403, "account_inactive", "Account is not active.");
    }

    const applicationRows = await sql`
      select a.code
      from ecosystem.app_enrollments e
      join ecosystem.applications a on a.id=e.application_id
      where e.account_id=${accountId}::uuid
        and e.status='Active'
      order by a.code
    `;

    const featureRows = await sql`
      select distinct f.code
      from commerce.entitlements e
      join commerce.features f on f.id=e.feature_id
      where e.status='Active'
        and e.starts_at_utc <= now()
        and (e.expires_at_utc is null or e.expires_at_utc > now())
        and (e.grantee_account_id is null or e.grantee_account_id=${accountId}::uuid)
        and (
          e.beneficiary_person_id is null
          or e.beneficiary_person_id=(
            select l.person_id
            from core.account_person_links l
            where l.account_id=${accountId}::uuid
              and l.link_type='Self'
              and l.status='Active'
            order by l.created_at_utc, l.person_id
            limit 1
          )
        )
      order by f.code
    `;

    return {
      accountId,
      selfPersonId: typeof account.self_person_id === "string"
        ? account.self_person_id
        : null,
      applications: applicationRows.map((row) => String(row.code)),
      features: featureRows.map((row) => String(row.code)),
    };
  }

  return { requirePersonFeature, capabilitySnapshot };
}

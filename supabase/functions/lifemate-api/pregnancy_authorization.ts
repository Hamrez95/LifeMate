import { getLifeMateSql } from "./database_client.ts";
import { ApiError } from "./validation.ts";

export const pregnancyScopes = [
  "pregnancy.summary.read",
  "pregnancy.calendar.read",
  "pregnancy.observations.read",
  "pregnancy.appointments.read",
  "pregnancy.medications.read",
  "pregnancy.documents.read",
  "pregnancy.support.write",
  "pregnancy.owner.manage",
] as const;

export type PregnancyScope = (typeof pregnancyScopes)[number];

export function isPregnancyScope(value: string): value is PregnancyScope {
  return (pregnancyScopes as readonly string[]).includes(value);
}

export function isOwnerOnlyPregnancyScope(scope: PregnancyScope): boolean {
  return scope === "pregnancy.owner.manage";
}

export function createPregnancyAuthorization(databaseUrl: string) {
  const sql = getLifeMateSql(databaseUrl);

  async function hasAccess(args: {
    callerAccountId: string;
    subjectPersonId: string;
    episodeId: string | null;
    scope: PregnancyScope;
  }): Promise<boolean> {
    const rows = await sql`
      select security.can_access_pregnancy_scope(
        ${args.callerAccountId}::uuid,
        ${args.subjectPersonId}::uuid,
        ${args.episodeId}::uuid,
        ${args.scope}::varchar,
        now()
      ) as allowed
    `;
    return rows[0]?.allowed === true;
  }

  async function requireAccess(args: {
    callerAccountId: string;
    subjectPersonId: string;
    episodeId: string | null;
    scope: PregnancyScope;
  }): Promise<void> {
    if (!(await hasAccess(args))) {
      throw new ApiError(
        403,
        "pregnancy_access_denied",
        "Pregnancy access is not authorized.",
      );
    }
  }

  return { hasAccess, requireAccess };
}

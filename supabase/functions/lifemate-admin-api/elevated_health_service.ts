import { type AdminSql, getAdminSql } from "./database_client.ts";
import type { ElevatedHealthQuery } from "./elevated_health.ts";
import { ApiError } from "./validation.ts";

function result(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new ApiError(
      503,
      "elevated_health_unavailable",
      "Elevated health read result was unavailable.",
    );
  }
  const parsed = value as Record<string, unknown>;
  if (!Number.isInteger(parsed.httpStatus) || typeof parsed.code !== "string") {
    throw new ApiError(
      503,
      "elevated_health_unavailable",
      "Elevated health read result was invalid.",
    );
  }
  return parsed;
}

export function createElevatedHealthStore(databaseUrl: string) {
  const sql: AdminSql = getAdminSql(databaseUrl);
  return {
    async read(input: {
      actorAccountId: string;
      query: ElevatedHealthQuery;
      correlationId: string;
    }) {
      const rows = await sql`
        select admin.read_elevated_health_summary(
          ${input.actorAccountId}::uuid,
          ${input.query.subjectPersonId}::uuid,
          ${input.query.capability}::character varying,
          ${input.correlationId}::uuid,
          ${input.query.limit}::integer
        ) as result
      `;
      return result(rows[0]?.result);
    },
  };
}

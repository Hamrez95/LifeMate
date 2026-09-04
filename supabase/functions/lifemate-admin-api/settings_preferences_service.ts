import { type AdminSql, getAdminSql } from "./database_client.ts";
import type { ConfigureCommandCenterPreferencesPayload } from "./settings_preferences.ts";
import { ApiError } from "./validation.ts";

function iso(value: unknown): string {
  return value instanceof Date ? value.toISOString() : String(value);
}

function mutationResult(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new ApiError(
      503,
      "settings_workflow_unavailable",
      "Settings workflow result was unavailable.",
    );
  }
  const row = value as Record<string, unknown>;
  if (
    !Number.isInteger(row.httpStatus) || typeof row.code !== "string" ||
    typeof row.replayed !== "boolean"
  ) {
    throw new ApiError(
      503,
      "settings_workflow_unavailable",
      "Settings workflow result was invalid.",
    );
  }
  return row;
}

export function createCommandCenterPreferencesStore(databaseUrl: string) {
  const sql: AdminSql = getAdminSql(databaseUrl);
  return {
    async get() {
      const rows =
        await sql`select * from admin.get_command_center_preferences()`;
      const value = (rows as unknown as Record<string, unknown>[])[0];
      if (!value) {
        throw new ApiError(
          503,
          "settings_unavailable",
          "Command Center preferences are unavailable.",
        );
      }
      return {
        locale: String(value.locale),
        timeZone: String(value.time_zone),
        displayName: String(value.display_name),
        version: Number(value.version),
        updatedAtUtc: value.updated_at_utc == null
          ? null
          : iso(value.updated_at_utc),
      };
    },

    async configure(input: {
      actorAccountId: string;
      payload: ConfigureCommandCenterPreferencesPayload;
      correlationId: string;
      idempotencyKey: string;
      requestHash: string;
    }) {
      const p = input.payload;
      const rows = await sql`
        select admin.configure_command_center_preferences(
          ${input.actorAccountId}::uuid,
          ${p.locale}::character varying,
          ${p.timeZone}::character varying,
          ${p.displayName}::character varying,
          ${p.expectedVersion}::integer,
          ${p.reason}::character varying,
          ${input.correlationId}::uuid,
          ${input.idempotencyKey}::character varying,
          ${input.requestHash}::character varying
        ) as result
      `;
      return mutationResult(rows[0]?.result);
    },
  };
}

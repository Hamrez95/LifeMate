import { type AdminSql, getAdminSql } from "./database_client.ts";
import type { ConfigureFinanceScenarioPayload } from "./finance_scenarios.ts";
import { ApiError } from "./validation.ts";

function iso(value: unknown): string {
  return value instanceof Date ? value.toISOString() : String(value);
}

function mutationResult(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new ApiError(503, "finance_scenario_workflow_unavailable", "Finance scenario workflow result was unavailable.");
  }
  const row = value as Record<string, unknown>;
  if (!Number.isInteger(row.httpStatus) || typeof row.code !== "string" || typeof row.replayed !== "boolean") {
    throw new ApiError(503, "finance_scenario_workflow_unavailable", "Finance scenario workflow result was invalid.");
  }
  return row;
}

function scenarioRow(row: Record<string, unknown>) {
  const assumptions = row.assumptions_json;
  if (!Array.isArray(assumptions)) {
    throw new ApiError(503, "finance_scenario_data_invalid", "Finance scenario data was invalid.");
  }
  return {
    scenarioId: String(row.scenario_id),
    scenarioKind: String(row.scenario_kind),
    name: String(row.name),
    currency: String(row.currency).trim(),
    validFrom: String(row.valid_from),
    validTo: String(row.valid_to),
    version: Number(row.version),
    assumptions,
    createdAtUtc: iso(row.created_at_utc),
    updatedAtUtc: iso(row.updated_at_utc),
  };
}

export function createFinanceScenarioStore(databaseUrl: string) {
  const sql: AdminSql = getAdminSql(databaseUrl);
  return {
    async list() {
      const rows = await sql`select * from admin.get_finance_scenarios()`;
      return (rows as unknown as Record<string, unknown>[]).map(scenarioRow);
    },

    async configure(input: {
      actorAccountId: string;
      scenarioId: string | null;
      payload: ConfigureFinanceScenarioPayload;
      correlationId: string;
      idempotencyKey: string;
      requestHash: string;
    }) {
      const p = input.payload;
      const rows = await sql`
        select admin.configure_finance_scenario(
          ${input.actorAccountId}::uuid,
          ${input.scenarioId}::uuid,
          ${p.scenarioKind}::character varying,
          ${p.name}::character varying,
          ${p.currency}::character,
          ${p.validFrom}::date,
          ${p.validTo}::date,
          ${JSON.stringify(p.assumptions)}::jsonb,
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

import { getAdminSql } from "./database_client.ts";
import type {
  MarketingChannelItem,
  MarketingChannelStatusPayload,
} from "./marketing_channels.ts";
import { ApiError } from "./validation.ts";

type ChannelRow = {
  provider_code: string;
  display_name: string;
  operator_status: "Enabled" | "Disabled";
  setup_status: "SetupRequired" | "CredentialAvailable" | "Disabled";
  credential_available: boolean;
  updated_at_utc: Date | string;
};

function iso(value: Date | string): string {
  return value instanceof Date ? value.toISOString() : new Date(value).toISOString();
}

function mapChannel(row: ChannelRow): MarketingChannelItem {
  return {
    providerCode: row.provider_code,
    displayName: row.display_name,
    operatorStatus: row.operator_status,
    setupStatus: row.setup_status,
    credentialAvailable: Boolean(row.credential_available),
    providerConnectivity: "NotVerified",
    updatedAtUtc: iso(row.updated_at_utc),
  };
}

function assertMutationResult(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new ApiError(
      503,
      "marketing_channel_workflow_unavailable",
      "Channel workflow result was unavailable.",
    );
  }
  const result = value as Record<string, unknown>;
  if (
    !Number.isInteger(result.httpStatus) ||
    typeof result.code !== "string" ||
    typeof result.replayed !== "boolean"
  ) {
    throw new ApiError(
      503,
      "marketing_channel_workflow_unavailable",
      "Channel workflow result was invalid.",
    );
  }
  return result;
}

export function createMarketingChannelStore(databaseUrl: string) {
  const sql = getAdminSql(databaseUrl);

  return {
    async list(): Promise<MarketingChannelItem[]> {
      const rows = await sql<ChannelRow[]>`
        select
          provider_code,
          display_name,
          operator_status,
          setup_status,
          credential_available,
          updated_at_utc
        from admin.marketing_channel_connections_v1
        order by display_name asc, provider_code asc
        limit 100
      `;
      return rows.map(mapChannel);
    },

    async setStatus(input: {
      actorAccountId: string;
      providerCode: string;
      payload: MarketingChannelStatusPayload;
      correlationId: string;
      idempotencyKey: string;
      requestHash: string;
    }) {
      const rows = await sql`
        select admin.set_marketing_channel_operator_status(
          ${input.actorAccountId}::uuid,
          ${input.providerCode}::varchar,
          ${input.payload.enabled}::boolean,
          ${input.payload.reason}::varchar,
          ${input.correlationId}::uuid,
          ${input.idempotencyKey}::varchar,
          ${input.requestHash}::varchar
        ) as result
      `;
      return assertMutationResult(rows[0]?.result);
    },
  };
}

export type MarketingChannelStore = ReturnType<typeof createMarketingChannelStore>;

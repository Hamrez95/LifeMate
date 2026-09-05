import { type AdminSql, getAdminSql } from "./database_client.ts";
import type {
  CreateCatalogBundlePayload,
  CreateCatalogOfferPayload,
  ScheduleOfferPricePayload,
  UpdateCatalogBundlePayload,
  UpdateCatalogOfferPayload,
  UpdateCatalogProductPayload,
  UpsertCatalogPolicyPayload,
} from "./commerce_catalog_v2_mutations.ts";
import { ApiError } from "./validation.ts";

function result(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new ApiError(
      503,
      "commerce_catalog_v2_workflow_unavailable",
      "Commerce catalog v2 mutation result was unavailable.",
    );
  }
  const row = value as Record<string, unknown>;
  if (
    !Number.isInteger(row.httpStatus) || typeof row.code !== "string" ||
    typeof row.replayed !== "boolean"
  ) {
    throw new ApiError(
      503,
      "commerce_catalog_v2_workflow_unavailable",
      "Commerce catalog v2 mutation result was invalid.",
    );
  }
  return row;
}

export function createCommerceCatalogV2MutationStore(databaseUrl: string) {
  const sql: AdminSql = getAdminSql(databaseUrl);
  return {
    async updateProduct(
      input: {
        actorAccountId: string;
        productId: string;
        payload: UpdateCatalogProductPayload;
        correlationId: string;
        idempotencyKey: string;
        requestHash: string;
      },
    ) {
      const p = input.payload;
      const rows =
        await sql`select admin.update_commerce_catalog_product(${input.actorAccountId}::uuid,${input.productId}::uuid,${p.name}::varchar,${p.status}::varchar,${p.expectedVersion}::bigint,${p.reason}::varchar,${input.correlationId}::uuid,${input.idempotencyKey}::varchar,${input.requestHash}::varchar) as result`;
      return result(rows[0]?.result);
    },
    async createOffer(
      input: {
        actorAccountId: string;
        payload: CreateCatalogOfferPayload;
        correlationId: string;
        idempotencyKey: string;
        requestHash: string;
      },
    ) {
      const p = input.payload;
      const rows =
        await sql`select admin.create_commerce_catalog_offer(${input.actorAccountId}::uuid,${p.productId}::uuid,${p.code}::varchar,${p.name}::varchar,${p.durationMonths}::smallint,${p.status}::varchar,${p.giftEligible}::boolean,${p.reason}::varchar,${input.correlationId}::uuid,${input.idempotencyKey}::varchar,${input.requestHash}::varchar) as result`;
      return result(rows[0]?.result);
    },
    async updateOffer(
      input: {
        actorAccountId: string;
        offerId: string;
        payload: UpdateCatalogOfferPayload;
        correlationId: string;
        idempotencyKey: string;
        requestHash: string;
      },
    ) {
      const p = input.payload;
      const rows =
        await sql`select admin.update_commerce_catalog_offer(${input.actorAccountId}::uuid,${input.offerId}::uuid,${p.name}::varchar,${p.durationMonths}::smallint,${p.status}::varchar,${p.giftEligible}::boolean,${p.expectedVersion}::bigint,${p.reason}::varchar,${input.correlationId}::uuid,${input.idempotencyKey}::varchar,${input.requestHash}::varchar) as result`;
      return result(rows[0]?.result);
    },
    async scheduleOfferPrice(
      input: {
        actorAccountId: string;
        offerId: string;
        payload: ScheduleOfferPricePayload;
        correlationId: string;
        idempotencyKey: string;
        requestHash: string;
      },
    ) {
      const p = input.payload;
      const rows =
        await sql`select admin.schedule_commerce_offer_price(${input.actorAccountId}::uuid,${input.offerId}::uuid,${p.countryCode}::varchar,${p.currency}::varchar,${p.storeProvider}::varchar,${p.amountMinor}::bigint,${p.effectiveFromUtc}::timestamptz,${p.reason}::varchar,${input.correlationId}::uuid,${input.idempotencyKey}::varchar,${input.requestHash}::varchar) as result`;
      return result(rows[0]?.result);
    },
    async upsertPolicy(
      input: {
        actorAccountId: string;
        productId: string;
        policyKey: string;
        payload: UpsertCatalogPolicyPayload;
        correlationId: string;
        idempotencyKey: string;
        requestHash: string;
      },
    ) {
      const p = input.payload;
      const rows =
        await sql`select admin.upsert_commerce_catalog_policy(${input.actorAccountId}::uuid,${input.productId}::uuid,${input.policyKey}::varchar,${
          JSON.stringify(p.value)
        }::jsonb,${p.valueType}::varchar,${p.status}::varchar,${p.expectedVersion}::bigint,${p.reason}::varchar,${input.correlationId}::uuid,${input.idempotencyKey}::varchar,${input.requestHash}::varchar) as result`;
      return result(rows[0]?.result);
    },
    async createBundle(
      input: {
        actorAccountId: string;
        payload: CreateCatalogBundlePayload;
        correlationId: string;
        idempotencyKey: string;
        requestHash: string;
      },
    ) {
      const p = input.payload;
      const rows =
        await sql`select admin.create_commerce_catalog_bundle(${input.actorAccountId}::uuid,${p.code}::varchar,${p.name}::varchar,${p.status}::varchar,${p.giftEligible}::boolean,${p.offerIds}::uuid[],${p.reason}::varchar,${input.correlationId}::uuid,${input.idempotencyKey}::varchar,${input.requestHash}::varchar) as result`;
      return result(rows[0]?.result);
    },
    async updateBundle(
      input: {
        actorAccountId: string;
        bundleId: string;
        payload: UpdateCatalogBundlePayload;
        correlationId: string;
        idempotencyKey: string;
        requestHash: string;
      },
    ) {
      const p = input.payload;
      const rows =
        await sql`select admin.update_commerce_catalog_bundle(${input.actorAccountId}::uuid,${input.bundleId}::uuid,${p.name}::varchar,${p.status}::varchar,${p.giftEligible}::boolean,${p.offerIds}::uuid[],${p.expectedVersion}::bigint,${p.reason}::varchar,${input.correlationId}::uuid,${input.idempotencyKey}::varchar,${input.requestHash}::varchar) as result`;
      return result(rows[0]?.result);
    },
  };
}

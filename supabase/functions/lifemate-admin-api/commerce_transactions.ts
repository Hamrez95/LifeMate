import { ApiError, boundedInteger } from "./validation.ts";

export const TRANSACTION_STATUSES = [
  "Pending",
  "Succeeded",
  "Failed",
  "Cancelled",
  "Refunded",
  "Chargeback",
] as const;

export type TransactionStatus = (typeof TRANSACTION_STATUSES)[number];

export type CommerceTransactionsQuery = {
  page: number;
  pageSize: number;
  offset: number;
  product: string | null;
  provider: string | null;
  status: TransactionStatus | null;
  fromUtc: string | null;
  toUtc: string | null;
  referenceId: string | null;
};

const CODE = /^[A-Za-z0-9][A-Za-z0-9._:-]{0,63}$/;
const UUID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const STATUS_SET = new Set<string>(TRANSACTION_STATUSES);

function optionalCode(value: string | null, field: string): string | null {
  const normalized = value?.trim() ?? "";
  if (!normalized) return null;
  if (!CODE.test(normalized)) {
    throw new ApiError(
      400,
      `commerce_${field}_invalid`,
      `Commerce ${field} filter is invalid.`,
    );
  }
  return normalized;
}

function optionalDate(value: string | null, field: string): string | null {
  const normalized = value?.trim() ?? "";
  if (!normalized) return null;
  const date = new Date(normalized);
  if (Number.isNaN(date.getTime())) {
    throw new ApiError(
      400,
      `commerce_${field}_invalid`,
      `Commerce ${field} filter is invalid.`,
    );
  }
  return date.toISOString();
}

export function parseCommerceTransactionsQuery(
  url: URL,
): CommerceTransactionsQuery {
  const page = boundedInteger(url.searchParams.get("page"), 1, 1, 100_000);
  const pageSize = boundedInteger(url.searchParams.get("pageSize"), 25, 5, 100);
  const product = optionalCode(url.searchParams.get("product"), "product");
  const provider = optionalCode(url.searchParams.get("provider"), "provider");

  const rawStatus = url.searchParams.get("status")?.trim() ?? "";
  if (rawStatus && !STATUS_SET.has(rawStatus)) {
    throw new ApiError(
      400,
      "commerce_transaction_status_invalid",
      "Transaction status filter is invalid.",
    );
  }

  const fromUtc = optionalDate(url.searchParams.get("from"), "from");
  const toUtc = optionalDate(url.searchParams.get("to"), "to");
  if (fromUtc && toUtc && fromUtc > toUtc) {
    throw new ApiError(
      400,
      "commerce_transaction_range_invalid",
      "Transaction date range is invalid.",
    );
  }

  const rawReference = url.searchParams.get("q")?.trim() ?? "";
  if (rawReference && !UUID.test(rawReference)) {
    throw new ApiError(
      400,
      "commerce_transaction_reference_invalid",
      "Reference search accepts exact internal UUIDs only.",
    );
  }

  return {
    page,
    pageSize,
    offset: (page - 1) * pageSize,
    product,
    provider,
    status: rawStatus ? (rawStatus as TransactionStatus) : null,
    fromUtc,
    toUtc,
    referenceId: rawReference || null,
  };
}

import { ApiError } from "./validation.ts";

export const COMMERCE_CATALOG_V2_VERSION = "2026-08-26";

export type CommerceCatalogV2Query = {
  product: string | null;
  includeHidden: boolean;
};

const PRODUCT_CODE = /^[a-z0-9][a-z0-9._-]{1,63}$/;

export function parseCommerceCatalogV2Query(url: URL): CommerceCatalogV2Query {
  const rawProduct = url.searchParams.get("product")?.trim().toLowerCase() ??
    "";
  if (rawProduct && !PRODUCT_CODE.test(rawProduct)) {
    throw new ApiError(
      400,
      "commerce_product_invalid",
      "Commerce product filter is invalid.",
    );
  }
  const rawHidden = url.searchParams.get("includeHidden")?.trim().toLowerCase();
  if (rawHidden != null && rawHidden !== "true" && rawHidden !== "false") {
    throw new ApiError(
      400,
      "commerce_include_hidden_invalid",
      "includeHidden must be true or false.",
    );
  }
  return {
    product: rawProduct || null,
    includeHidden: rawHidden === "true",
  };
}

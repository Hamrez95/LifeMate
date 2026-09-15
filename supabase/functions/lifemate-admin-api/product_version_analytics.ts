import { ApiError } from "./validation.ts";

const products = new Set(["wellmate", "caremate"]);
const platforms = new Set([
  "android",
  "ios",
  "web",
  "windows",
  "macos",
  "linux",
  "unknown",
]);
const uuid =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export type ProductVersionAdoptionQuery = {
  product: string | null;
  platform: string | null;
};

export function parseProductVersionAdoptionQuery(
  url: URL,
): ProductVersionAdoptionQuery {
  const productRaw = url.searchParams.get("product")?.trim().toLowerCase() ??
    "";
  const platformRaw = url.searchParams.get("platform")?.trim().toLowerCase() ??
    "";
  if (productRaw && !products.has(productRaw)) {
    throw new ApiError(400, "product_invalid", "product is invalid.");
  }
  if (platformRaw && !platforms.has(platformRaw)) {
    throw new ApiError(400, "platform_invalid", "platform is invalid.");
  }
  return {
    product: productRaw || null,
    platform: platformRaw || null,
  };
}

export function matchAccountProductVersionsPath(path: string): string | null {
  const match = path.match(
    /^\/api\/v1\/analytics\/accounts\/([0-9a-f-]{36})\/product-versions$/i,
  );
  if (!match || !uuid.test(match[1])) return null;
  return match[1].toLowerCase();
}

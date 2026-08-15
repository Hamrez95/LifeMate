import { ApiError, boundedInteger } from "./validation.ts";

export const globalSearchDomains = [
  "users",
  "support",
  "commerce",
  "campaigns",
] as const;
export type GlobalSearchDomain = (typeof globalSearchDomains)[number];

export type GlobalSearchQuery = {
  q: string;
  domains: GlobalSearchDomain[];
  page: number;
  pageSize: number;
};

export type GlobalSearchItem = {
  id: string;
  domain: GlobalSearchDomain;
  kind: string;
  title: string;
  subtitle: string | null;
  status: string | null;
  badge: string | null;
  href: string;
};

export type GlobalSearchGroup = {
  domain: GlobalSearchDomain;
  availability: "ready" | "unavailable";
  items: GlobalSearchItem[];
  total: number | null;
  page: number;
  pageSize: number;
  unavailableReason?: "not_instrumented";
};

const DOMAIN_SET = new Set<string>(globalSearchDomains);
const SAFE_QUERY_PATTERN = /^[^\u0000-\u001f\u007f]{3,80}$/u;

export const globalSearchPermission: Record<GlobalSearchDomain, string> = {
  users: "users.read.basic",
  support: "support.read",
  commerce: "commerce.read",
  campaigns: "marketing.read",
};

export function parseGlobalSearchQuery(url: URL): GlobalSearchQuery {
  const q = (url.searchParams.get("q") ?? "").trim().replace(/\s+/g, " ");
  if (!SAFE_QUERY_PATTERN.test(q)) {
    throw new ApiError(
      400,
      "search_query_invalid",
      "Search query must contain between 3 and 80 visible characters.",
    );
  }

  const rawTypes =
    (url.searchParams.get("types") ?? globalSearchDomains.join(","))
      .split(",")
      .map((item) => item.trim().toLowerCase())
      .filter(Boolean);
  if (rawTypes.length < 1 || rawTypes.length > globalSearchDomains.length) {
    throw new ApiError(
      400,
      "search_types_invalid",
      "Search domain selection is invalid.",
    );
  }
  const unique = [...new Set(rawTypes)];
  if (unique.some((item) => !DOMAIN_SET.has(item))) {
    throw new ApiError(
      400,
      "search_types_invalid",
      "Search domain selection is invalid.",
    );
  }

  return {
    q,
    domains: unique as GlobalSearchDomain[],
    page: boundedInteger(url.searchParams.get("page"), 1, 1, 1000),
    pageSize: boundedInteger(url.searchParams.get("pageSize"), 5, 1, 10),
  };
}

export function authorizedSearchDomains(
  requested: readonly GlobalSearchDomain[],
  permissions: readonly string[],
): GlobalSearchDomain[] {
  const granted = new Set(permissions);
  return requested.filter((domain) =>
    granted.has(globalSearchPermission[domain])
  );
}

export function safeSearchLogFields(
  query: GlobalSearchQuery,
  authorized: GlobalSearchDomain[],
) {
  return {
    queryLength: [...query.q].length,
    requestedDomains: query.domains,
    authorizedDomains: authorized,
    page: query.page,
    pageSize: query.pageSize,
  };
}

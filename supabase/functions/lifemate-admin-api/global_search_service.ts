import { type AdminSql, getAdminSql } from "./database_client.ts";
import type {
  GlobalSearchDomain,
  GlobalSearchGroup,
  GlobalSearchItem,
  GlobalSearchQuery,
} from "./global_search.ts";

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const CODE_PATTERN = /^[A-Z0-9][A-Z0-9._-]{2,63}$/;

type Row = Record<string, unknown>;

type RateLimitResult = {
  allowed: boolean;
  remaining: number;
  retryAfterSeconds: number;
};

function nullableString(value: unknown): string | null {
  return typeof value === "string" && value.length > 0 ? value : null;
}

function result(
  domain: GlobalSearchDomain,
  row: Row,
): GlobalSearchItem {
  return {
    id: String(row.id),
    domain,
    kind: String(row.kind),
    title: String(row.title),
    subtitle: nullableString(row.subtitle),
    status: nullableString(row.status),
    badge: nullableString(row.badge),
    href: String(row.href),
  };
}

function readyGroup(
  domain: GlobalSearchDomain,
  query: GlobalSearchQuery,
  total: number,
  rows: Row[],
): GlobalSearchGroup {
  return {
    domain,
    availability: "ready",
    items: rows.map((row) => result(domain, row)),
    total,
    page: query.page,
    pageSize: query.pageSize,
  };
}

async function searchUsers(
  sql: AdminSql,
  query: GlobalSearchQuery,
): Promise<GlobalSearchGroup> {
  const offset = (query.page - 1) * query.pageSize;
  const exactAccountId = UUID_PATTERN.test(query.q)
    ? query.q.toLowerCase()
    : null;
  const countRows = await sql`
    select count(*)::integer as total
    from admin.user_directory_v1
    where strpos(lower(coalesce(display_name, '')), lower(${query.q})) > 0
       or (${exactAccountId}::uuid is not null and account_id = ${exactAccountId}::uuid)
  `;
  const rows = await sql`
    select
      account_id::text as id,
      'user'::text as kind,
      coalesce(nullif(display_name, ''), 'کاربر بدون نام')::text as title,
      case
        when cardinality(application_codes) > 0 then array_to_string(application_codes, ' · ')
        else null
      end::text as subtitle,
      account_status::text as status,
      null::text as badge,
      ('/users/' || account_id::text)::text as href
    from admin.user_directory_v1
    where strpos(lower(coalesce(display_name, '')), lower(${query.q})) > 0
       or (${exactAccountId}::uuid is not null and account_id = ${exactAccountId}::uuid)
    order by
      case when lower(coalesce(display_name, '')) = lower(${query.q}) then 0 else 1 end,
      last_active_at_utc desc nulls last,
      account_id asc
    limit ${query.pageSize}
    offset ${offset}
  `;
  return readyGroup(
    "users",
    query,
    Number(countRows[0]?.total ?? 0),
    rows as unknown as Row[],
  );
}

async function searchSupport(
  sql: AdminSql,
  query: GlobalSearchQuery,
): Promise<GlobalSearchGroup> {
  const offset = (query.page - 1) * query.pageSize;
  const numericTicket = /^#?\d{1,18}$/.test(query.q)
    ? Number(query.q.replace(/^#/, ""))
    : null;
  const countRows = await sql`
    select count(*)::integer as total
    from admin.support_ticket_queue_v1
    where (${numericTicket}::bigint is not null and ticket_number = ${numericTicket}::bigint)
       or strpos(lower(coalesce(requester_display_name, '')), lower(${query.q})) > 0
       or strpos(lower(coalesce(queue_summary_redacted, '')), lower(${query.q})) > 0
  `;
  const rows = await sql`
    select
      ticket_id::text as id,
      'support_ticket'::text as kind,
      ('#' || ticket_number::text || ' · ' || coalesce(nullif(queue_summary_redacted, ''), category))::text as title,
      case
        when requester_display_name is null then product_code
        when product_code is null then requester_display_name
        else requester_display_name || ' · ' || product_code
      end::text as subtitle,
      status::text as status,
      priority::text as badge,
      ('/support/' || ticket_id::text)::text as href
    from admin.support_ticket_queue_v1
    where (${numericTicket}::bigint is not null and ticket_number = ${numericTicket}::bigint)
       or strpos(lower(coalesce(requester_display_name, '')), lower(${query.q})) > 0
       or strpos(lower(coalesce(queue_summary_redacted, '')), lower(${query.q})) > 0
    order by
      case when ${numericTicket}::bigint is not null and ticket_number = ${numericTicket}::bigint then 0 else 1 end,
      last_activity_at_utc desc,
      ticket_id asc
    limit ${query.pageSize}
    offset ${offset}
  `;
  return readyGroup(
    "support",
    query,
    Number(countRows[0]?.total ?? 0),
    rows as unknown as Row[],
  );
}

async function searchCommerce(
  sql: AdminSql,
  query: GlobalSearchQuery,
): Promise<GlobalSearchGroup> {
  const offset = (query.page - 1) * query.pageSize;
  const exactUuid = UUID_PATTERN.test(query.q) ? query.q.toLowerCase() : null;
  const exactCode = CODE_PATTERN.test(query.q.toUpperCase())
    ? query.q.toUpperCase()
    : null;

  const countRows = await sql`
    with results as (
      select ('plan:' || pl.id::text)::text as result_key
      from commerce.plans pl
      join commerce.products product on product.id = pl.product_id
      where strpos(lower(pl.display_name), lower(${query.q})) > 0
         or strpos(lower(pl.code), lower(${query.q})) > 0
         or strpos(lower(product.display_name), lower(${query.q})) > 0
         or strpos(lower(product.code), lower(${query.q})) > 0
      union all
      select ('feature:' || feature.code)::text
      from commerce.features feature
      where strpos(lower(feature.code), lower(${query.q})) > 0
      union all
      select ('promotion:' || promotion.id::text)::text
      from commerce.promotions promotion
      where strpos(lower(promotion.name), lower(${query.q})) > 0
         or (
           ${exactCode}::text is not null
           and exists (
             select 1 from commerce.discount_codes dc
             where dc.promotion_id = promotion.id
               and lower(dc.code) = lower(${exactCode})
           )
         )
      union all
      select ('transaction:' || tx.id::text)::text
      from commerce.transactions tx
      where ${exactUuid}::uuid is not null and tx.id = ${exactUuid}::uuid
    )
    select count(*)::integer as total from results
  `;

  const rows = await sql`
    with results as (
      select
        pl.id::text as id,
        'plan'::text as kind,
        (pl.display_name || ' · ' || pl.code)::text as title,
        (product.display_name || ' · ' || product.code)::text as subtitle,
        pl.status::text as status,
        'Plan'::text as badge,
        ('/commerce/plans/' || pl.id::text)::text as href,
        case
          when lower(pl.code) = lower(${query.q}) then 0
          when lower(pl.display_name) = lower(${query.q}) then 1
          else 3
        end::integer as rank
      from commerce.plans pl
      join commerce.products product on product.id = pl.product_id
      where strpos(lower(pl.display_name), lower(${query.q})) > 0
         or strpos(lower(pl.code), lower(${query.q})) > 0
         or strpos(lower(product.display_name), lower(${query.q})) > 0
         or strpos(lower(product.code), lower(${query.q})) > 0

      union all

      select
        feature.code::text as id,
        'entitlement_feature'::text as kind,
        feature.code::text as title,
        'Entitlement feature'::text as subtitle,
        null::text as status,
        'Entitlement'::text as badge,
        ('/commerce/entitlements/' || feature.code)::text as href,
        case when lower(feature.code) = lower(${query.q}) then 0 else 3 end::integer as rank
      from commerce.features feature
      where strpos(lower(feature.code), lower(${query.q})) > 0

      union all

      select
        promotion.id::text as id,
        'promotion'::text as kind,
        promotion.name::text as title,
        case
          when product.id is null then 'همه محصولات'
          else product.display_name || ' · ' || product.code
        end::text as subtitle,
        case
          when promotion.ends_at_utc is not null and promotion.ends_at_utc <= now() then 'Expired'
          else promotion.status
        end::text as status,
        'Promotion'::text as badge,
        ('/commerce/promotions/' || promotion.id::text)::text as href,
        case
          when lower(promotion.name) = lower(${query.q}) then 0
          when ${exactCode}::text is not null and exists (
            select 1 from commerce.discount_codes dc
            where dc.promotion_id = promotion.id
              and lower(dc.code) = lower(${exactCode})
          ) then 1
          else 3
        end::integer as rank
      from commerce.promotions promotion
      left join commerce.products product on product.id = promotion.product_id
      where strpos(lower(promotion.name), lower(${query.q})) > 0
         or (
           ${exactCode}::text is not null
           and exists (
             select 1 from commerce.discount_codes dc
             where dc.promotion_id = promotion.id
               and lower(dc.code) = lower(${exactCode})
           )
         )

      union all

      select
        tx.id::text as id,
        'transaction'::text as kind,
        ('تراکنش ' || left(tx.id::text, 8) || '…')::text as title,
        (product.display_name || ' · ' || tx.provider)::text as subtitle,
        tx.normalized_status::text as status,
        'Transaction'::text as badge,
        ('/commerce/transactions/' || tx.id::text)::text as href,
        0::integer as rank
      from commerce.transactions tx
      join commerce.products product on product.id = tx.product_id
      where ${exactUuid}::uuid is not null and tx.id = ${exactUuid}::uuid
    )
    select id, kind, title, subtitle, status, badge, href
    from results
    order by rank asc, lower(title) asc, id asc
    limit ${query.pageSize}
    offset ${offset}
  `;

  return readyGroup(
    "commerce",
    query,
    Number(countRows[0]?.total ?? 0),
    rows as unknown as Row[],
  );
}

export function createGlobalSearchStore(databaseUrl: string) {
  const sql = getAdminSql(databaseUrl);
  return {
    async consumeRateLimit(accountId: string): Promise<RateLimitResult> {
      const rows = await sql`
        select allowed, remaining, retry_after_seconds
        from admin.consume_search_rate_limit(${accountId}::uuid, 60, 60)
      `;
      const row = rows[0] as Row | undefined;
      return {
        allowed: Boolean(row?.allowed),
        remaining: Number(row?.remaining ?? 0),
        retryAfterSeconds: Number(row?.retry_after_seconds ?? 60),
      };
    },

    async search(
      query: GlobalSearchQuery,
      domains: readonly GlobalSearchDomain[],
    ): Promise<GlobalSearchGroup[]> {
      const groups: GlobalSearchGroup[] = [];
      for (const domain of domains) {
        if (domain === "users") groups.push(await searchUsers(sql, query));
        else if (domain === "support") {
          groups.push(await searchSupport(sql, query));
        } else if (domain === "commerce") {
          groups.push(await searchCommerce(sql, query));
        } else if (domain === "campaigns") {
          groups.push({
            domain: "campaigns",
            availability: "unavailable",
            items: [],
            total: null,
            page: query.page,
            pageSize: query.pageSize,
            unavailableReason: "not_instrumented",
          });
        }
      }
      return groups;
    },
  };
}

import type { AdminSql } from "./database_client.ts";
import type { UserDirectoryQuery } from "./directory.ts";

type DirectoryRow = Record<string, unknown>;

export type UserDirectoryItem = {
  accountId: string;
  personId: string | null;
  displayName: string | null;
  status: string;
  applicationCodes: string[];
  createdAtUtc: string;
  lastActiveAtUtc: string | null;
};

export type UserDirectoryResult = {
  items: UserDirectoryItem[];
  total: number;
};

function escapeLike(value: string): string {
  return value.replace(/[\\%_]/g, "\\$&");
}

function asIso(value: unknown): string {
  return value instanceof Date ? value.toISOString() : String(value);
}

function asNullableIso(value: unknown): string | null {
  return value == null ? null : asIso(value);
}

function asStringArray(value: unknown): string[] {
  return Array.isArray(value)
    ? value.filter((item): item is string => typeof item === "string")
    : [];
}

export async function listUserDirectory(
  sql: AdminSql,
  query: UserDirectoryQuery,
): Promise<UserDirectoryResult> {
  const searchPattern = query.search ? `%${escapeLike(query.search)}%` : null;
  const searchUuid = query.search &&
      /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(
        query.search,
      )
    ? query.search.toLowerCase()
    : null;

  const countRows = await sql`
    select count(*)::integer as total
    from admin.user_directory_v1
    where (${query.status}::text is null or account_status = ${query.status})
      and (${query.application}::text is null or ${query.application} = any(application_codes))
      and (
        ${searchPattern}::text is null
        or display_name ilike ${searchPattern} escape '\\'
        or (${searchUuid}::uuid is not null and account_id = ${searchUuid}::uuid)
      )
  `;

  const rows = await sql`
    select account_id, person_id, display_name, account_status, application_codes,
           created_at_utc, last_active_at_utc
    from admin.user_directory_v1
    where (${query.status}::text is null or account_status = ${query.status})
      and (${query.application}::text is null or ${query.application} = any(application_codes))
      and (
        ${searchPattern}::text is null
        or display_name ilike ${searchPattern} escape '\\'
        or (${searchUuid}::uuid is not null and account_id = ${searchUuid}::uuid)
      )
    order by
      case when ${query.sort} = 'displayName' and ${query.direction} = 'asc'
        then lower(display_name) end asc nulls last,
      case when ${query.sort} = 'displayName' and ${query.direction} = 'desc'
        then lower(display_name) end desc nulls last,
      case when ${query.sort} = 'lastActiveAt' and ${query.direction} = 'asc'
        then last_active_at_utc end asc nulls last,
      case when ${query.sort} = 'lastActiveAt' and ${query.direction} = 'desc'
        then last_active_at_utc end desc nulls last,
      case when ${query.sort} = 'createdAt' and ${query.direction} = 'asc'
        then created_at_utc end asc,
      case when ${query.sort} = 'createdAt' and ${query.direction} = 'desc'
        then created_at_utc end desc,
      account_id asc
    limit ${query.pageSize}
    offset ${query.offset}
  `;

  return {
    total: Number(countRows[0]?.total ?? 0),
    items: (rows as unknown as DirectoryRow[]).map((row) => ({
      accountId: String(row.account_id),
      personId: typeof row.person_id === "string" ? row.person_id : null,
      displayName: typeof row.display_name === "string" ? row.display_name : null,
      status: String(row.account_status),
      applicationCodes: asStringArray(row.application_codes),
      createdAtUtc: asIso(row.created_at_utc),
      lastActiveAtUtc: asNullableIso(row.last_active_at_utc),
    })),
  };
}

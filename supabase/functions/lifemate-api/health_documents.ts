import { getLifeMateSql } from "./database_client.ts";
import { ApiError, requiredUuid } from "./validation.ts";

type Row = Record<string, unknown>;

export type HealthDocumentCategory =
  | "prescription"
  | "lab_result"
  | "imaging"
  | "visit"
  | "injection"
  | "discharge"
  | "vaccination"
  | "other";

export type HealthDocumentRegistration = {
  documentId: string;
  objectKey: string;
  contentType: string;
  byteSize: number;
  sha256Hex: string;
  category: HealthDocumentCategory;
  capturedOn: string | null;
  sourceProduct: string;
  link: HealthDocumentLink | null;
};

/** The only contexts that may be attached from the creation forms. */
export type HealthDocumentLink = {
  contextType: "treatment_plan" | "care_event";
  contextId: string;
};

export type HealthDocumentListQuery = {
  category: HealthDocumentCategory | null;
  sourceProduct: string | null;
  fromDate: string | null;
  toDate: string | null;
  cursor: string | null;
  limit: number;
};

type DocumentCursor = { createdAtUtc: string; id: string };

const allowedCategories = new Set<HealthDocumentCategory>([
  "prescription",
  "lab_result",
  "imaging",
  "visit",
  "injection",
  "discharge",
  "vaccination",
  "other",
]);

/**
 * The persistence boundary for Health Record documents. This store never
 * accepts file bytes; the private Storage runtime owns bytes, and Postgres only
 * keeps opaque object keys plus reviewed metadata.
 */
export function createHealthDocumentStore(databaseUrl: string) {
  const sql = getLifeMateSql(databaseUrl);

  async function ownerIdentity(connection: any, appUserId: string) {
    const rows = await connection`
      select
        identity.account_id_for_legacy_app_user(${appUserId}::uuid)::text
          as account_id,
        core.self_person_id_for_legacy_app_user(${appUserId}::uuid)::text
          as person_id
    `;
    const accountId = rows[0]?.account_id;
    const personId = rows[0]?.person_id;
    if (typeof accountId !== "string" || typeof personId !== "string") {
      throw new ApiError(
        409,
        "self_person_missing",
        "A self health profile is required before adding a document.",
      );
    }
    return { accountId, personId };
  }

  async function registerOwnerUpload(
    appUserId: string,
    input: HealthDocumentRegistration,
  ): Promise<{ created: boolean; document: Record<string, unknown> }> {
    validateRegistration(input);
    return await sql.begin(async (tx: any) => {
      const { accountId, personId } = await ownerIdentity(tx, appUserId);
      const inserted = await tx`
        insert into lifemate.health_documents
          (id, owner_person_id, storage_object_key, content_type, byte_size,
           sha256_hex, category, source_product, captured_on, status,
           created_by_account_id, created_at_utc, updated_at_utc)
        values
          (${input.documentId}::uuid, ${personId}::uuid, ${input.objectKey},
           ${input.contentType}, ${input.byteSize}::integer,
           ${input.sha256Hex}::char(64), ${input.category},
           ${input.sourceProduct}, ${input.capturedOn}::date, 'Available',
           ${accountId}::uuid, now(), now())
        on conflict (owner_person_id, sha256_hex) do nothing
        returning *
      `;
      if (inserted[0]) {
        await tx`
          insert into lifemate.health_document_audit_events
            (id, document_id, actor_account_id, action, metadata_json)
          values
            (${crypto.randomUUID()}::uuid, ${input.documentId}::uuid,
             ${accountId}::uuid, 'Uploaded',
             ${
          JSON.stringify({
            category: input.category,
            sourceProduct: input.sourceProduct,
          })
        }::jsonb)
        `;
        await linkDocument(tx, input.documentId, accountId, input.link);
        return { created: true, document: mapDocument(inserted[0]) };
      }
      const existing = await tx`
        select * from lifemate.health_documents
        where owner_person_id = ${personId}::uuid
          and sha256_hex = ${input.sha256Hex}::char(64)
          and status = 'Available'
        limit 1
      `;
      if (!existing[0]) {
        throw new ApiError(
          409,
          "health_document_conflict",
          "The document could not be resolved after upload.",
        );
      }
      await linkDocument(tx, String(existing[0].id), accountId, input.link);
      return { created: false, document: mapDocument(existing[0]) };
    });
  }

  // Keyset pagination keeps a changing record chronological and bounded. Its
  // opaque cursor contains only a timestamp and UUID — never document metadata.
  async function listOwnerDocuments(
    appUserId: string,
    query: HealthDocumentListQuery,
  ) {
    const { personId } = await ownerIdentity(sql, appUserId);
    const cursor = parseDocumentCursor(query.cursor);
    const rows = await sql`
      select d.*,
        coalesce(jsonb_agg(jsonb_build_object(
          'contextType', l.context_type,
          'contextId', l.context_id
        )) filter (where l.document_id is not null), '[]'::jsonb) as links
      from lifemate.health_documents d
      left join lifemate.health_document_links l on l.document_id = d.id
      where d.owner_person_id = ${personId}::uuid
        and d.status = 'Available'
        and (${query.category}::text is null or d.category = ${query.category})
        and (${query.sourceProduct}::text is null or d.source_product = ${query.sourceProduct})
        and (${query.fromDate}::date is null
          or coalesce(d.captured_on, d.created_at_utc::date) >= ${query.fromDate}::date)
        and (${query.toDate}::date is null
          or coalesce(d.captured_on, d.created_at_utc::date) <= ${query.toDate}::date)
        and (
          ${cursor?.createdAtUtc ?? null}::timestamptz is null
          or (d.created_at_utc, d.id) < (
            ${cursor?.createdAtUtc ?? null}::timestamptz,
            ${cursor?.id ?? null}::uuid
          )
        )
      group by d.id
      order by d.created_at_utc desc, d.id desc
      limit ${query.limit + 1}
    `;
    const hasMore = rows.length > query.limit;
    const items = rows.slice(0, query.limit).map(mapDocument);
    const last = rows[Math.min(rows.length, query.limit) - 1];
    return {
      items,
      nextCursor: hasMore && last ? encodeDocumentCursor(last) : null,
    };
  }

  async function authorizedSubject(
  connection: any,
  appUserId: string,
  subjectPersonIdValue: unknown,
) {
  const requester = await ownerIdentity(connection, appUserId);
  const subjectPersonId = subjectPersonIdValue == null ||
      String(subjectPersonIdValue).trim().length === 0
    ? requester.personId
    : requiredUuid(subjectPersonIdValue, "personId");
  const rows = await connection`
    select security.can_access_health_document_scope(
      ${requester.accountId}::uuid,
      ${subjectPersonId}::uuid,
      'health_record.documents.read'
    ) as allowed
  `;
  if (rows[0]?.allowed !== true) {
    throw new ApiError(
      403,
      "health_document_access_denied",
      "Explicit Health Record document access is required.",
    );
  }
  return { accountId: requester.accountId, personId: subjectPersonId };
}

async function listDocuments(
  appUserId: string,
  subjectPersonIdValue: unknown,
  query: HealthDocumentListQuery,
) {
  const { personId } = await authorizedSubject(
    sql,
    appUserId,
    subjectPersonIdValue,
  );
  const cursor = parseDocumentCursor(query.cursor);
  const rows = await sql`
    select d.*,
      coalesce(jsonb_agg(jsonb_build_object(
        'contextType', l.context_type,
        'contextId', l.context_id
      )) filter (where l.document_id is not null), '[]'::jsonb) as links
    from lifemate.health_documents d
    left join lifemate.health_document_links l on l.document_id = d.id
    where d.owner_person_id = ${personId}::uuid
      and d.status = 'Available'
      and (${query.category}::text is null or d.category = ${query.category})
      and (${query.sourceProduct}::text is null or d.source_product = ${query.sourceProduct})
      and (${query.fromDate}::date is null
        or coalesce(d.captured_on, d.created_at_utc::date) >= ${query.fromDate}::date)
      and (${query.toDate}::date is null
        or coalesce(d.captured_on, d.created_at_utc::date) <= ${query.toDate}::date)
      and (
        ${cursor?.createdAtUtc ?? null}::timestamptz is null
        or (d.created_at_utc, d.id) < (
          ${cursor?.createdAtUtc ?? null}::timestamptz,
          ${cursor?.id ?? null}::uuid
        )
      )
    group by d.id
    order by d.created_at_utc desc, d.id desc
    limit ${query.limit + 1}
  `;
  const hasMore = rows.length > query.limit;
  const items = rows.slice(0, query.limit).map(mapDocument);
  const last = rows[Math.min(rows.length, query.limit) - 1];
  return {
    items,
    nextCursor: hasMore && last ? encodeDocumentCursor(last) : null,
  };
}

async function getAuthorizedDownload(
  appUserId: string,
  documentIdValue: unknown,
) {
  const documentId = requiredUuid(documentIdValue, "documentId");
  return await sql.begin(async (tx: any) => {
    const requester = await ownerIdentity(tx, appUserId);
    const rows = await tx`
      select d.*
      from lifemate.health_documents d
      where d.id = ${documentId}::uuid
        and d.status = 'Available'
        and security.can_access_health_document_scope(
          ${requester.accountId}::uuid,
          d.owner_person_id,
          'health_record.documents.read'
        )
      limit 1
    `;
    if (!rows[0]) {
      throw new ApiError(
        404,
        "health_document_not_found",
        "Document was not found.",
      );
    }
    await tx`
      insert into lifemate.health_document_audit_events
        (id, document_id, actor_account_id, action)
      values
        (${crypto.randomUUID()}::uuid, ${documentId}::uuid,
         ${requester.accountId}::uuid, 'Downloaded')
    `;
    return {
      ...mapDocument(rows[0]),
      storageObjectKey: String(rows[0].storage_object_key),
    };
  });
}

  async function ownerForUpload(appUserId: string) {
    return await ownerIdentity(sql, appUserId);
  }

  async function getOwnerDownload(appUserId: string, documentIdValue: unknown) {
    const documentId = requiredUuid(documentIdValue, "documentId");
    return await sql.begin(async (tx: any) => {
      const { accountId, personId } = await ownerIdentity(tx, appUserId);
      const rows = await tx`
        select * from lifemate.health_documents
        where id = ${documentId}::uuid
          and owner_person_id = ${personId}::uuid
          and status = 'Available'
        limit 1
      `;
      if (!rows[0]) {
        throw new ApiError(
          404,
          "health_document_not_found",
          "Document was not found.",
        );
      }
      await tx`
        insert into lifemate.health_document_audit_events
          (id, document_id, actor_account_id, action)
        values
          (${crypto.randomUUID()}::uuid, ${documentId}::uuid,
           ${accountId}::uuid, 'Downloaded')
      `;
      return {
        ...mapDocument(rows[0]),
        storageObjectKey: String(rows[0].storage_object_key),
      };
    });
  }

  return {
    ownerForUpload,
    registerOwnerUpload,
    listOwnerDocuments,
    getOwnerDownload,
    listDocuments,
    getAuthorizedDownload,
  };
}

export function parseHealthDocumentListQuery(
  value: URLSearchParams,
): HealthDocumentListQuery {
  const categoryValue = value.get("category")?.trim().toLowerCase() ?? "";
  const category = categoryValue.length === 0
    ? null
    : allowedCategories.has(categoryValue as HealthDocumentCategory)
    ? categoryValue as HealthDocumentCategory
    : invalidListQuery("category");
  const sourceProduct = normalizeOptionalSource(value.get("sourceProduct"));
  const fromDate = optionalListDate(value.get("fromDate"), "fromDate");
  const toDate = optionalListDate(value.get("toDate"), "toDate");
  if (fromDate && toDate && fromDate > toDate) {
    throw new ApiError(
      400,
      "health_document_date_range_invalid",
      "Date range is invalid.",
    );
  }
  const rawLimit = value.get("limit");
  const parsedLimit = rawLimit == null || rawLimit.trim() === ""
    ? 25
    : Number(rawLimit);
  if (!Number.isInteger(parsedLimit) || parsedLimit < 1 || parsedLimit > 100) {
    throw new ApiError(
      400,
      "health_document_limit_invalid",
      "Document list limit is invalid.",
    );
  }
  const cursor = value.get("cursor")?.trim() || null;
  if (cursor) parseDocumentCursor(cursor);
  return {
    category,
    sourceProduct,
    fromDate,
    toDate,
    cursor,
    limit: parsedLimit,
  };
}

function invalidListQuery(field: string): never {
  throw new ApiError(
    400,
    "health_document_filter_invalid",
    `${field} filter is invalid.`,
  );
}

function normalizeOptionalSource(value: string | null): string | null {
  const normalized = value?.trim().toLowerCase() ?? "";
  if (normalized.length === 0) return null;
  if (!/^[a-z0-9][a-z0-9_-]{0,39}$/.test(normalized)) {
    return invalidListQuery("sourceProduct");
  }
  return normalized;
}

function optionalListDate(value: string | null, field: string): string | null {
  if (value == null || value.trim() === "") return null;
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return invalidListQuery(field);
  return value;
}

function parseDocumentCursor(value: string | null): DocumentCursor | null {
  if (!value) return null;
  try {
    const decoded = JSON.parse(atob(value)) as Record<string, unknown>;
    const createdAtUtc = typeof decoded.createdAtUtc === "string"
      ? decoded.createdAtUtc
      : "";
    const id = typeof decoded.id === "string" ? decoded.id : "";
    if (
      Number.isNaN(Date.parse(createdAtUtc)) || !/^[0-9a-f-]{36}$/i.test(id)
    ) {
      throw new Error("invalid");
    }
    return { createdAtUtc, id };
  } catch (_) {
    throw new ApiError(
      400,
      "health_document_cursor_invalid",
      "Document list cursor is invalid.",
    );
  }
}

function encodeDocumentCursor(row: Row): string {
  return btoa(
    JSON.stringify({
      createdAtUtc: iso(row.created_at_utc),
      id: String(row.id),
    }),
  );
}

function validateRegistration(input: HealthDocumentRegistration): void {
  requiredUuid(input.documentId, "documentId");
  if (
    !/^[0-9a-f-]{36}\/[0-9a-f-]{36}\/[0-9a-f-]{36}\.(jpg|png|webp|heic|pdf)$/i
      .test(
        input.objectKey,
      )
  ) {
    throw new ApiError(
      400,
      "health_document_path_invalid",
      "Document path is invalid.",
    );
  }
  if (
    !/^image\/(jpeg|png|webp|heic)$|^application\/pdf$/.test(input.contentType)
  ) {
    throw new ApiError(
      400,
      "health_document_type_invalid",
      "Document type is invalid.",
    );
  }
  if (
    !Number.isInteger(input.byteSize) ||
    input.byteSize < 1 ||
    input.byteSize > 15 * 1024 * 1024
  ) {
    throw new ApiError(
      400,
      "health_document_size_invalid",
      "Document size is invalid.",
    );
  }
  if (!/^[0-9a-f]{64}$/.test(input.sha256Hex)) {
    throw new ApiError(
      400,
      "health_document_hash_invalid",
      "Document hash is invalid.",
    );
  }
  if (!allowedCategories.has(input.category)) {
    throw new ApiError(
      400,
      "health_document_category_invalid",
      "Document category is invalid.",
    );
  }
  if (
    input.capturedOn !== null &&
    !/^\d{4}-\d{2}-\d{2}$/.test(input.capturedOn)
  ) {
    throw new ApiError(
      400,
      "health_document_date_invalid",
      "Document date is invalid.",
    );
  }
  if (!/^[a-z0-9][a-z0-9_-]{0,39}$/.test(input.sourceProduct)) {
    throw new ApiError(
      400,
      "health_document_source_invalid",
      "Document source is invalid.",
    );
  }
  validateLink(input.link);
}

/**
 * The DB trigger rechecks that the selected context is owned by the same
 * Person. This parsing boundary keeps the polymorphic pair deliberately
 * narrow before it reaches that trigger.
 */
export function parseHealthDocumentLink(
  contextTypeValue: string | null,
  contextIdValue: string | null,
): HealthDocumentLink | null {
  const contextType = contextTypeValue?.trim().toLowerCase() ?? "";
  const contextId = contextIdValue?.trim() ?? "";
  if (!contextType && !contextId) return null;
  if (!contextType || !contextId) {
    throw new ApiError(
      400,
      "health_document_link_invalid",
      "Document context type and identifier must be supplied together.",
    );
  }
  if (contextType !== "treatment_plan" && contextType !== "care_event") {
    throw new ApiError(
      400,
      "health_document_link_invalid",
      "Document context type is invalid.",
    );
  }
  requiredUuid(contextId, "contextId");
  return { contextType, contextId };
}

function validateLink(link: HealthDocumentLink | null): void {
  if (link === null) return;
  parseHealthDocumentLink(link.contextType, link.contextId);
}

async function linkDocument(
  tx: any,
  documentId: string,
  accountId: string,
  link: HealthDocumentLink | null,
): Promise<void> {
  if (link === null) return;
  const linked = await tx`
    insert into lifemate.health_document_links
      (document_id, context_type, context_id)
    values
      (${documentId}::uuid, ${link.contextType}, ${link.contextId}::uuid)
    on conflict do nothing
    returning document_id
  `;
  if (!linked[0]) return;
  await tx`
    insert into lifemate.health_document_audit_events
      (id, document_id, actor_account_id, action, metadata_json)
    values
      (${crypto.randomUUID()}::uuid, ${documentId}::uuid,
       ${accountId}::uuid, 'Linked',
       ${JSON.stringify(link)}::jsonb)
  `;
}

function mapDocument(row: Row): Record<string, unknown> {
  return {
    id: String(row.id),
    ownerPersonId: String(row.owner_person_id),
    contentType: String(row.content_type),
    byteSize: Number(row.byte_size),
    category: String(row.category),
    sourceProduct: String(row.source_product),
    capturedOn: row.captured_on == null
      ? null
      : String(row.captured_on).slice(0, 10),
    links: row.links ?? [],
    createdAtUtc: iso(row.created_at_utc),
  };
}

function iso(value: unknown): string {
  return value instanceof Date
    ? value.toISOString()
    : new Date(String(value)).toISOString();
}

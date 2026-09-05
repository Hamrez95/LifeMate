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

  async function listOwnerDocuments(appUserId: string) {
    const { personId } = await ownerIdentity(sql, appUserId);
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
      group by d.id
      order by d.created_at_utc desc, d.id desc
      limit 500
    `;
    return rows.map(mapDocument);
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
  };
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

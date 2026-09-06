import { getLifeMateSql } from "./database_client.ts";
import { ApiError, requiredUuid } from "./validation.ts";

export const healthDocumentSharingConsentVersion =
  "health-record-documents-sharing-v1";
const readScope = "health_record.documents.read";
const consentPurpose = "health_record_sharing";
const grantContextType = "health_record_relationship";

type Row = Record<string, unknown>;

export type HealthDocumentSharingUpdate = {
  canViewDocuments: boolean;
  confirmConsent: boolean;
  consentVersion: string | null;
};

export function createHealthDocumentSharingStore(databaseUrl: string) {
  const sql = getLifeMateSql(databaseUrl);

  async function identity(connection: any, appUserId: string) {
    const rows = await connection`
      select
        identity.account_id_for_legacy_app_user(${appUserId}::uuid)::text as account_id,
        core.self_person_id_for_legacy_app_user(${appUserId}::uuid)::text as person_id
    `;
    const accountId = rows[0]?.account_id;
    const personId = rows[0]?.person_id;
    if (typeof accountId !== "string" || typeof personId !== "string") {
      throw new ApiError(
        409,
        "self_person_missing",
        "A self health profile is required before managing document sharing.",
      );
    }
    return { accountId, personId };
  }

  async function relationship(
    connection: any,
    relationshipId: string,
    requesterPersonId: string,
    ownerOnly: boolean,
    lock = false,
  ): Promise<Row> {
    const rows = lock
      ? await connection`
          select r.*,
            coalesce(r.patient_person_id,
              core.self_person_id_for_legacy_app_user(r.patient_user_id))::text
              as resolved_patient_person_id,
            coalesce(r.caregiver_person_id,
              core.self_person_id_for_legacy_app_user(r.caregiver_user_id))::text
              as resolved_caregiver_person_id,
            identity.account_id_for_legacy_app_user(r.caregiver_user_id)::text
              as caregiver_account_id
          from lifemate.care_relationships r
          where r.id = ${relationshipId}::uuid
            and r.status = 'Active'
            and (
              coalesce(r.patient_person_id,
                core.self_person_id_for_legacy_app_user(r.patient_user_id)) =
                ${requesterPersonId}::uuid
              ${ownerOnly
                ? sql``
                : sql`or coalesce(r.caregiver_person_id,
                    core.self_person_id_for_legacy_app_user(r.caregiver_user_id)) =
                    ${requesterPersonId}::uuid`}
            )
          for update
        `
      : await connection`
          select r.*,
            coalesce(r.patient_person_id,
              core.self_person_id_for_legacy_app_user(r.patient_user_id))::text
              as resolved_patient_person_id,
            coalesce(r.caregiver_person_id,
              core.self_person_id_for_legacy_app_user(r.caregiver_user_id))::text
              as resolved_caregiver_person_id,
            identity.account_id_for_legacy_app_user(r.caregiver_user_id)::text
              as caregiver_account_id
          from lifemate.care_relationships r
          where r.id = ${relationshipId}::uuid
            and r.status = 'Active'
            and (
              coalesce(r.patient_person_id,
                core.self_person_id_for_legacy_app_user(r.patient_user_id)) =
                ${requesterPersonId}::uuid
              ${ownerOnly
                ? sql``
                : sql`or coalesce(r.caregiver_person_id,
                    core.self_person_id_for_legacy_app_user(r.caregiver_user_id)) =
                    ${requesterPersonId}::uuid`}
            )
          limit 1
        `;
    if (!rows[0]) {
      throw new ApiError(
        404,
        "relationship_not_found",
        ownerOnly
          ? "Active owner care relationship was not found."
          : "Active care relationship was not found.",
      );
    }
    if (
      typeof rows[0].resolved_patient_person_id !== "string" ||
      typeof rows[0].caregiver_account_id !== "string"
    ) {
      throw new ApiError(
        409,
        "relationship_identity_incomplete",
        "Care relationship identity mapping is incomplete.",
      );
    }
    return rows[0];
  }

  function consentScopeKey(relationshipId: string, caregiverAccountId: string) {
    return `health_record_relationship:${relationshipId}:grantee:${caregiverAccountId}`;
  }

  async function currentState(
    connection: any,
    row: Row,
  ): Promise<Record<string, unknown>> {
    const relationshipId = String(row.id);
    const patientPersonId = String(row.resolved_patient_person_id);
    const caregiverAccountId = String(row.caregiver_account_id);
    const scopeKey = consentScopeKey(relationshipId, caregiverAccountId);
    const rows = await connection`
      select
        exists(
          select 1
          from security.access_grants g
          join security.access_grant_scopes gs
            on gs.grant_id = g.id and gs.scope = ${readScope}
          join consent.consent_records c
            on c.subject_person_id = g.subject_person_id
           and c.purpose = ${consentPurpose}
           and c.scope_key = ${scopeKey}
           and c.status = 'Granted'
           and c.granted_at_utc <= now()
           and (c.expires_at_utc is null or c.expires_at_utc > now())
          where g.subject_person_id = ${patientPersonId}::uuid
            and g.grantee_account_id = ${caregiverAccountId}::uuid
            and g.context_type = ${grantContextType}
            and g.context_id = ${relationshipId}::uuid
            and g.status = 'Active'
            and g.starts_at_utc <= now()
            and (g.expires_at_utc is null or g.expires_at_utc > now())
        ) as can_view_documents,
        (
          select d.version::text
          from consent.consent_records c
          join consent.consent_documents d on d.id = c.document_id
          where c.subject_person_id = ${patientPersonId}::uuid
            and c.purpose = ${consentPurpose}
            and c.scope_key = ${scopeKey}
          order by c.updated_at_utc desc
          limit 1
        ) as consent_version,
        (
          select c.granted_at_utc
          from consent.consent_records c
          where c.subject_person_id = ${patientPersonId}::uuid
            and c.purpose = ${consentPurpose}
            and c.scope_key = ${scopeKey}
          order by c.updated_at_utc desc
          limit 1
        ) as consented_at_utc,
        (
          select c.revoked_at_utc
          from consent.consent_records c
          where c.subject_person_id = ${patientPersonId}::uuid
            and c.purpose = ${consentPurpose}
            and c.scope_key = ${scopeKey}
          order by c.updated_at_utc desc
          limit 1
        ) as revoked_at_utc
    `;
    const state = rows[0] ?? {};
    return {
      relationshipId,
      patientPersonId,
      canViewDocuments: state.can_view_documents === true,
      consentVersion: state.consent_version == null
        ? null
        : String(state.consent_version),
      consentedAtUtc: isoOrNull(state.consented_at_utc),
      revokedAtUtc: isoOrNull(state.revoked_at_utc),
      accessMode: "read_only",
    };
  }

  async function getPermission(appUserId: string, relationshipIdValue: unknown) {
    const relationshipId = requiredUuid(relationshipIdValue, "relationshipId");
    const requester = await identity(sql, appUserId);
    const row = await relationship(
      sql,
      relationshipId,
      requester.personId,
      false,
    );
    return await currentState(sql, row);
  }

  async function updatePermission(
    appUserId: string,
    relationshipIdValue: unknown,
    update: HealthDocumentSharingUpdate,
  ) {
    const relationshipId = requiredUuid(relationshipIdValue, "relationshipId");
    if (
      update.canViewDocuments &&
      (update.confirmConsent !== true ||
        update.consentVersion !== healthDocumentSharingConsentVersion)
    ) {
      throw new ApiError(
        400,
        "health_document_sharing_consent_required",
        "Explicit patient consent is required to share Health Record documents.",
      );
    }

    return await sql.begin(async (tx: any) => {
      const requester = await identity(tx, appUserId);
      const row = await relationship(
        tx,
        relationshipId,
        requester.personId,
        true,
        true,
      );
      const patientPersonId = String(row.resolved_patient_person_id);
      const caregiverAccountId = String(row.caregiver_account_id);
      const scopeKey = consentScopeKey(relationshipId, caregiverAccountId);

      const documentRows = await tx`
        select id
        from consent.consent_documents
        where purpose = ${consentPurpose}
          and version = ${healthDocumentSharingConsentVersion}
          and jurisdiction = '*'
          and status = 'Active'
        limit 1
      `;
      if (!documentRows[0]) {
        throw new ApiError(
          503,
          "health_document_sharing_policy_unavailable",
          "Health Record sharing policy is not available.",
        );
      }
      const consentDocumentId = String(documentRows[0].id);

      const grantRows = await tx`
        insert into security.access_grants(
          subject_person_id, grantee_account_id, grantor_person_id,
          context_type, context_id, status, starts_at_utc, expires_at_utc,
          revoked_at_utc, created_at_utc, updated_at_utc
        ) values (
          ${patientPersonId}::uuid, ${caregiverAccountId}::uuid,
          ${patientPersonId}::uuid, ${grantContextType},
          ${relationshipId}::uuid,
          ${update.canViewDocuments ? "Active" : "Revoked"}, now(), null,
          ${update.canViewDocuments ? null : new Date().toISOString()}::timestamptz,
          now(), now()
        )
        on conflict(subject_person_id, grantee_account_id, context_type, context_id)
        do update set
          grantor_person_id = excluded.grantor_person_id,
          status = excluded.status,
          starts_at_utc = case
            when excluded.status = 'Active' then now()
            else security.access_grants.starts_at_utc
          end,
          expires_at_utc = null,
          revoked_at_utc = excluded.revoked_at_utc,
          updated_at_utc = now()
        returning id
      `;
      const grantId = String(grantRows[0].id);
      if (update.canViewDocuments) {
        await tx`
          insert into security.access_grant_scopes(grant_id, scope)
          values (${grantId}::uuid, ${readScope})
          on conflict do nothing
        `;
      }

      const consentRows = await tx`
        select id, status
        from consent.consent_records
        where subject_person_id = ${patientPersonId}::uuid
          and purpose = ${consentPurpose}
          and scope_key = ${scopeKey}
        order by created_at_utc desc
        limit 1
        for update
      `;
      const previousStatus = consentRows[0]?.status == null
        ? null
        : String(consentRows[0].status);
      const nextStatus = update.canViewDocuments ? "Granted" : "Revoked";
      let consentRecordId: string | null = consentRows[0]?.id == null
        ? null
        : String(consentRows[0].id);

      if (consentRecordId === null && update.canViewDocuments) {
        const inserted = await tx`
          insert into consent.consent_records(
            subject_person_id, actor_account_id, document_id, purpose, scope_key,
            data_categories, jurisdiction, source, status, granted_at_utc,
            revoked_at_utc, expires_at_utc, created_at_utc, updated_at_utc
          ) values (
            ${patientPersonId}::uuid, ${requester.accountId}::uuid,
            ${consentDocumentId}::uuid, ${consentPurpose}, ${scopeKey},
            array['health_documents']::character varying[], '*',
            'health_record_caregiver_setting', 'Granted', now(), null, null,
            now(), now()
          )
          returning id
        `;
        consentRecordId = String(inserted[0].id);
      } else if (consentRecordId !== null && previousStatus !== nextStatus) {
        await tx`
          update consent.consent_records
          set actor_account_id = ${requester.accountId}::uuid,
              document_id = ${consentDocumentId}::uuid,
              status = ${nextStatus},
              granted_at_utc = case
                when ${update.canViewDocuments} then now()
                else granted_at_utc
              end,
              revoked_at_utc = case
                when ${update.canViewDocuments} then null
                else now()
              end,
              expires_at_utc = null,
              updated_at_utc = now()
          where id = ${consentRecordId}::uuid
        `;
      }

      if (consentRecordId !== null && previousStatus !== nextStatus) {
        await tx`
          insert into consent.consent_events(
            consent_record_id, actor_account_id, event_type, occurred_at_utc
          ) values (
            ${consentRecordId}::uuid, ${requester.accountId}::uuid,
            ${nextStatus}, now()
          )
        `;
      }

      await tx`
        insert into lifemate.audit_logs(
          id, actor_user_id, action, resource_type, resource_id,
          metadata_json, created_at_utc
        ) values (
          ${crypto.randomUUID()}::uuid, ${appUserId}::uuid,
          ${update.canViewDocuments
            ? "health_record.documents.sharing_granted"
            : "health_record.documents.sharing_revoked"},
          'care_relationship', ${relationshipId}::uuid,
          ${JSON.stringify({
            scope: readScope,
            accessMode: "read_only",
            consentVersion: update.canViewDocuments
              ? healthDocumentSharingConsentVersion
              : null,
          })}::jsonb,
          now()
        )
      `;

      return await currentState(tx, row);
    });
  }

  return { getPermission, updatePermission };
}

export function parseHealthDocumentSharingUpdate(
  value: Record<string, unknown>,
): HealthDocumentSharingUpdate {
  if (typeof value.canViewDocuments !== "boolean") {
    throw new ApiError(
      400,
      "health_document_sharing_invalid",
      "canViewDocuments must be a boolean.",
    );
  }
  return {
    canViewDocuments: value.canViewDocuments,
    confirmConsent: value.confirmConsent === true,
    consentVersion: typeof value.consentVersion === "string"
      ? value.consentVersion.trim()
      : null,
  };
}

function isoOrNull(value: unknown): string | null {
  if (value == null) return null;
  const parsed = new Date(String(value));
  return Number.isNaN(parsed.getTime()) ? null : parsed.toISOString();
}

alter table lifemate.care_relationships
    add column if not exists can_manage_health_record boolean not null default false,
    add column if not exists health_record_management_consent_version character varying(64),
    add column if not exists health_record_management_consented_at_utc timestamp with time zone,
    add column if not exists health_record_management_revoked_at_utc timestamp with time zone;

do $migration$
begin
    if not exists (
        select 1
        from pg_constraint
        where conname = 'ck_care_relationship_health_record_consent'
          and conrelid = 'lifemate.care_relationships'::regclass
    ) then
        alter table lifemate.care_relationships
            add constraint ck_care_relationship_health_record_consent
            check (
                can_manage_health_record = false
                or (
                    health_record_management_consent_version is not null
                    and health_record_management_consented_at_utc is not null
                )
            );
    end if;
end
$migration$;

comment on column lifemate.care_relationships.can_manage_health_record is
'Owner-controlled explicit consent allowing the caregiver to create, edit and archive treatment plans and care events for the patient.';

comment on column lifemate.care_relationships.health_record_management_consent_version is
'Consent text version accepted by the patient when health-record management was granted.';

comment on column lifemate.care_relationships.health_record_management_consented_at_utc is
'UTC timestamp of the latest explicit patient grant for health-record management.';

comment on column lifemate.care_relationships.health_record_management_revoked_at_utc is
'UTC timestamp of the latest patient revocation for health-record management.';

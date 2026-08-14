export async function verifyDeepReadiness(sql: any): Promise<void> {
  const identity = await sql`
    select current_user as role_name,
           r.rolbypassrls,
           r.rolsuper,
           r.rolcreaterole,
           r.rolcreatedb,
           r.rolconnlimit
    from pg_roles r
    where r.rolname=current_user
    limit 1
  `;
  const role = identity[0];
  if (
    role?.role_name !== "lifemate_edge_runtime" ||
    role?.rolbypassrls !== false ||
    role?.rolsuper !== false ||
    role?.rolcreaterole !== false ||
    role?.rolcreatedb !== false ||
    Number(role?.rolconnlimit) !== 20
  ) {
    throw new Error("runtime_identity_not_restricted");
  }

  const applications = await sql`
    select code
    from ecosystem.applications
    where code='wellmate' and status='Active'
    limit 1
  `;
  if (applications[0]?.code !== "wellmate") {
    throw new Error("wellmate_application_missing");
  }

  const healthContract = await sql`
    select
      has_table_privilege(current_user, 'lifemate.health_observations', 'SELECT') as can_select,
      has_table_privilege(current_user, 'lifemate.health_observations', 'INSERT') as can_insert,
      has_table_privilege(current_user, 'lifemate.health_observations', 'UPDATE') as can_update,
      has_table_privilege(current_user, 'lifemate.health_observations', 'DELETE') as can_delete,
      exists (
        select 1
        from pg_policies
        where schemaname='lifemate'
          and tablename='health_observations'
          and policyname='lifemate_edge_runtime_access'
          and cmd='ALL'
          and 'lifemate_edge_runtime'=any(roles)
          and coalesce(qual, '')='true'
          and coalesce(with_check, '')='true'
      ) as expected_policy
  `;
  const health = healthContract[0];
  if (
    health?.can_select !== true ||
    health?.can_insert !== true ||
    health?.can_update !== true ||
    health?.can_delete !== true ||
    health?.expected_policy !== true
  ) {
    throw new Error("health_runtime_contract_broken");
  }

  await sql`select id from lifemate.health_observations where false`;
  await sql`select id from lifemate.dose_occurrences where false`;

  const probeId = crypto.randomUUID();
  await sql.begin(async (tx: any) => {
    const seed = await tx`
      select marker
      from security.runtime_readiness_probe
      where id='123e4567-e89b-42d3-a456-426614174888'::uuid
      limit 1
    `;
    if (seed[0]?.marker !== "lifemate-readiness-seed") {
      throw new Error("readiness_seed_not_visible");
    }
    await tx`
      insert into security.runtime_readiness_probe(id, marker)
      values (${probeId}::uuid, 'probe-created')
    `;
    const updated = await tx`
      update security.runtime_readiness_probe
      set marker='probe-updated', updated_at_utc=now()
      where id=${probeId}::uuid
      returning marker
    `;
    if (updated[0]?.marker !== "probe-updated") {
      throw new Error("readiness_update_failed");
    }
    const deleted = await tx`
      delete from security.runtime_readiness_probe
      where id=${probeId}::uuid
      returning id
    `;
    if (deleted.length !== 1) {
      throw new Error("readiness_delete_failed");
    }
  });
}

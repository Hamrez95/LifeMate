import { type AdminSql, getAdminSql } from "./database_client.ts";
import type {
  PlatformControlDefinition,
  PlatformControlRule,
} from "./platform_controls.ts";

type ControlSnapshot = {
  definition: PlatformControlDefinition;
  rules: PlatformControlRule[];
};

type CacheEntry = {
  value: ControlSnapshot | null;
  expiresAt: number;
};

const CACHE_TTL_MS = 15_000;
const CACHE_MAX_ENTRIES = 256;

export function createPlatformControlStore(databaseUrl: string) {
  const sql: AdminSql = getAdminSql(databaseUrl);
  const cache = new Map<string, CacheEntry>();

  function cacheGet(key: string): ControlSnapshot | null | undefined {
    const entry = cache.get(key);
    if (!entry) return undefined;
    if (entry.expiresAt <= Date.now()) {
      cache.delete(key);
      return undefined;
    }
    return entry.value;
  }

  function cacheSet(key: string, value: ControlSnapshot | null): void {
    if (cache.size >= CACHE_MAX_ENTRIES && !cache.has(key)) {
      const oldest = cache.keys().next().value;
      if (typeof oldest === "string") cache.delete(oldest);
    }
    cache.set(key, { value, expiresAt: Date.now() + CACHE_TTL_MS });
  }

  function invalidate(key?: string): void {
    if (key) cache.delete(key);
    else cache.clear();
  }

  return {
    invalidate,

    async list() {
      const controls = await sql`
        select control_key,control_kind,value_type,default_value,description,fail_closed,status,version,updated_at_utc
        from platform.controls
        where status <> 'Retired'
        order by control_key
      `;
      return controls.map((row) => ({
        key: String(row.control_key),
        kind: String(row.control_kind),
        valueType: String(row.value_type),
        defaultValue: row.default_value,
        description: String(row.description),
        failClosed: Boolean(row.fail_closed),
        status: String(row.status),
        version: Number(row.version),
        updatedAtUtc: new Date(String(row.updated_at_utc)).toISOString(),
      }));
    },

    async get(key: string): Promise<ControlSnapshot | null> {
      const cached = cacheGet(key);
      if (cached !== undefined) return cached;

      const controls = await sql`
        select control_key,control_kind,value_type,default_value,fail_closed,version
        from platform.controls where control_key=${key} and status='Active' limit 1
      `;
      if (controls.length === 0) {
        cacheSet(key, null);
        return null;
      }
      const row = controls[0];
      const rules = await sql`
        select id,priority,target_type,target_key,rollout_basis_points,value,starts_at_utc,ends_at_utc,version
        from platform.control_rules
        where control_key=${key} and status='Active'
        order by priority,id
      `;
      const snapshot: ControlSnapshot = {
        definition: {
          key: String(row.control_key),
          kind: String(row.control_kind) as PlatformControlDefinition["kind"],
          valueType: String(
            row.value_type,
          ) as PlatformControlDefinition["valueType"],
          defaultValue: row.default_value,
          failClosed: Boolean(row.fail_closed),
          version: Number(row.version),
        },
        rules: rules.map((r) => ({
          id: String(r.id),
          priority: Number(r.priority),
          targetType: String(
            r.target_type,
          ) as PlatformControlRule["targetType"],
          targetKey: r.target_key == null ? null : String(r.target_key),
          rolloutBasisPoints: r.rollout_basis_points == null
            ? null
            : Number(r.rollout_basis_points),
          value: r.value,
          startsAtUtc: r.starts_at_utc == null
            ? null
            : new Date(String(r.starts_at_utc)).toISOString(),
          endsAtUtc: r.ends_at_utc == null
            ? null
            : new Date(String(r.ends_at_utc)).toISOString(),
          version: Number(r.version),
        })),
      };
      cacheSet(key, snapshot);
      return snapshot;
    },
  };
}

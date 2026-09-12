Deno.test("admin capability snapshot uses one fail-closed database round trip", async () => {
  const source = await Deno.readTextFile(new URL("./store.ts", import.meta.url));
  const start = source.indexOf("async function getSnapshot(");
  const end = source.indexOf("async function bootstrapFounder(", start);
  if (start < 0 || end < 0) throw new Error("getSnapshot source block was not found");

  const block = source.slice(start, end);
  const sqlCalls = block.match(/await sql`/g) ?? [];
  if (sqlCalls.length !== 1) {
    throw new Error(`expected one admin snapshot SQL round trip, got ${sqlCalls.length}`);
  }

  for (const invariant of [
    "from admin.members",
    "m.status='Active'",
    "mr.revoked_at_utc is null",
    "mr.starts_at_utc <= now()",
    "mr.expires_at_utc is null or mr.expires_at_utc > now()",
    "r.status='Active'",
    "p.role_assignable=true",
    "admin_membership_required",
  ]) {
    if (!block.includes(invariant)) throw new Error(`missing authorization invariant: ${invariant}`);
  }

  if (!block.includes("snapshot?.is_active_member !== true")) {
    throw new Error("active membership must remain fail-closed");
  }
});

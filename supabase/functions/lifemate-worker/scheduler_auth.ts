type WorkerSql = any;

/**
 * Verifies the database-owned scheduler credential without exposing the Vault
 * secret to the Edge runtime. Missing infrastructure fails closed so manual
 * operator invocation can continue using LIFEMATE_WORKER_TOKEN during rollout.
 */
export async function schedulerTokenAccepted(
  sql: WorkerSql,
  suppliedToken: string,
): Promise<boolean> {
  if (suppliedToken.length < 32 || suppliedToken.length > 256) return false;
  try {
    const rows = await sql`
      select integration.verify_worker_scheduler_token(${suppliedToken}) as accepted
    `;
    return rows[0]?.accepted === true;
  } catch {
    return false;
  }
}

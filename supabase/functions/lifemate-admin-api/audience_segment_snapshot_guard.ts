import { getAdminSql } from "./database_client.ts";
import { ApiError } from "./validation.ts";

export async function withActiveSegmentVersionLock<T>(
  databaseUrl: string,
  segmentId: string,
  expectedVersion: number,
  work: () => Promise<T>,
): Promise<T> {
  const sql = getAdminSql(databaseUrl);

  return await sql.begin(async (tx) => {
    const rows = await tx`
      select id, version, status
      from audience.segments
      where id=${segmentId}::uuid
      for share
    `;

    if (rows.length === 0) {
      throw new ApiError(
        404,
        "segment_not_found",
        "Audience segment was not found.",
      );
    }

    if (String(rows[0].status) !== "Active") {
      throw new ApiError(
        409,
        "segment_not_active",
        "Audience segment must be active before creating an execution snapshot.",
      );
    }

    if (Number(rows[0].version) !== expectedVersion) {
      throw new ApiError(
        409,
        "segment_version_conflict",
        "Audience segment changed; refresh before creating an execution snapshot.",
      );
    }

    // Hold the SHARE lock until the snapshot transaction finishes. Segment updates
    // require a conflicting row lock, so the evaluated version cannot change or be
    // archived between the expected-version check and immutable snapshot creation.
    return await work();
  }) as T;
}

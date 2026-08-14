export type StorageFileEntry = {
  name: string;
  id?: string | null;
};

export type StorageFailure = {
  message?: string;
  status?: number;
  statusCode?: string | number;
};

export type ProfilePhotoBucket = {
  list(
    path: string,
    options: {
      limit: number;
      offset: number;
      sortBy: { column: "name"; order: "asc" };
    },
  ): Promise<{ data: StorageFileEntry[] | null; error: StorageFailure | null }>;
  remove(
    paths: string[],
  ): Promise<{ data?: unknown; error: StorageFailure | null }>;
};

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const maximumObjectsPerDelete = 1000;
const maximumDeleteBatches = 100;

/// Deletes every flat object under the service-owned `{appUserId}/` prefix.
/// Profile upload paths are generated server-side and never contain nested
/// folders. Encountering one fails closed rather than reporting a partial purge.
export async function purgeProfilePhotoFolder(
  bucket: ProfilePhotoBucket,
  appUserId: string,
): Promise<number> {
  if (!uuidPattern.test(appUserId)) {
    throw new Error("profile_photo_account_id_invalid");
  }

  let removed = 0;
  for (let batch = 0; batch < maximumDeleteBatches; batch++) {
    const listed = await bucket.list(appUserId, {
      limit: maximumObjectsPerDelete,
      offset: 0,
      sortBy: { column: "name", order: "asc" },
    });
    if (listed.error) {
      if (isMissingBucket(listed.error)) return removed;
      throw new Error("profile_photo_list_failed");
    }

    const entries = listed.data ?? [];
    if (entries.length === 0) return removed;

    const nested = entries.find((entry) => entry.id == null);
    if (nested) {
      throw new Error("profile_photo_nested_folder_unexpected");
    }

    const paths = entries.map((entry) => {
      const name = entry.name.trim();
      if (
        name.length === 0 || name.includes("/") || name.includes("..") ||
        !/^[0-9a-f-]{36}\.(jpg|png|webp)$/i.test(name)
      ) {
        throw new Error("profile_photo_object_name_invalid");
      }
      return `${appUserId}/${name}`;
    });

    if (paths.length === 0) return removed;
    const deleted = await bucket.remove(paths);
    if (deleted.error) throw new Error("profile_photo_delete_failed");
    removed += paths.length;

    if (paths.length < maximumObjectsPerDelete) return removed;
  }

  throw new Error("profile_photo_delete_batch_limit");
}

function isMissingBucket(error: StorageFailure): boolean {
  const status = Number(error.status ?? error.statusCode ?? 0);
  const message = String(error.message ?? "").toLowerCase();
  return status === 404 || message.includes("bucket not found");
}

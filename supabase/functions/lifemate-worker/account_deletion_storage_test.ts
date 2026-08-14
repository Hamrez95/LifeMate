import { assertEquals, assertRejects } from "jsr:@std/assert@1.0.14";
import {
  type ProfilePhotoBucket,
  purgeProfilePhotoFolder,
  type StorageFileEntry,
} from "./account_deletion_storage.ts";

class FakeBucket implements ProfilePhotoBucket {
  constructor(
    private readonly files: StorageFileEntry[],
    private readonly listError: { message?: string; status?: number } | null =
      null,
  ) {}

  removed: string[][] = [];

  async list() {
    if (this.listError) return { data: null, error: this.listError };
    return { data: [...this.files], error: null };
  }

  async remove(paths: string[]) {
    this.removed.push([...paths]);
    for (const path of paths) {
      const name = path.split("/").at(-1);
      const index = this.files.findIndex((entry) => entry.name === name);
      if (index >= 0) this.files.splice(index, 1);
    }
    return { error: null };
  }
}

Deno.test("purges every service-owned profile photo under the account prefix", async () => {
  const userId = "123e4567-e89b-42d3-a456-426614174000";
  const bucket = new FakeBucket([
    { name: "123e4567-e89b-42d3-a456-426614174001.jpg", id: "1" },
    { name: "123e4567-e89b-42d3-a456-426614174002.webp", id: "2" },
  ]);

  assertEquals(await purgeProfilePhotoFolder(bucket, userId), 2);
  assertEquals(bucket.removed, [[
    `${userId}/123e4567-e89b-42d3-a456-426614174001.jpg`,
    `${userId}/123e4567-e89b-42d3-a456-426614174002.webp`,
  ]]);
});

Deno.test("missing profile-photo bucket is equivalent to no stored objects", async () => {
  const bucket = new FakeBucket([], {
    message: "Bucket not found",
    status: 404,
  });
  assertEquals(
    await purgeProfilePhotoFolder(
      bucket,
      "123e4567-e89b-42d3-a456-426614174000",
    ),
    0,
  );
});

Deno.test("unexpected nested or malformed storage paths fail closed", async () => {
  await assertRejects(
    () =>
      purgeProfilePhotoFolder(
        new FakeBucket([{ name: "nested", id: null }]),
        "123e4567-e89b-42d3-a456-426614174000",
      ),
    Error,
    "profile_photo_nested_folder_unexpected",
  );
  await assertRejects(
    () =>
      purgeProfilePhotoFolder(
        new FakeBucket([{ name: "../../other-user.jpg", id: "1" }]),
        "123e4567-e89b-42d3-a456-426614174000",
      ),
    Error,
    "profile_photo_object_name_invalid",
  );
});

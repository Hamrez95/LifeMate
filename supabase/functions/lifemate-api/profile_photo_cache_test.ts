import { assertEquals } from "jsr:@std/assert@1.0.14";
import { createProfilePhotoStorage } from "./profile_photo.ts";

Deno.test("profile photo signed URLs are reused until the refresh window", async () => {
  const originalFetch = globalThis.fetch;
  const objectPath =
    "01805aff-0a88-49ce-b676-b914646c2072/01805aff-0a88-49ce-b676-b914646c2073.jpg";
  let bucketReads = 0;
  let signRequests = 0;
  let deletes = 0;

  globalThis.fetch = ((input: string | URL | Request, init?: RequestInit) => {
    const url = input.toString();
    const method = init?.method ?? "GET";
    if (
      method === "GET" &&
      url.endsWith("/storage/v1/bucket/profile-photos")
    ) {
      bucketReads += 1;
      return Promise.resolve(new Response("{}", { status: 200 }));
    }
    if (method === "POST" && url.includes("/storage/v1/object/sign/")) {
      signRequests += 1;
      return Promise.resolve(
        new Response(
          JSON.stringify({
            signedURL: `/storage/v1/object/sign/profile-photos/${objectPath}?token=${signRequests}`,
          }),
          { status: 200, headers: { "content-type": "application/json" } },
        ),
      );
    }
    if (
      method === "DELETE" &&
      url.endsWith("/storage/v1/object/profile-photos")
    ) {
      deletes += 1;
      return Promise.resolve(new Response("{}", { status: 200 }));
    }
    return Promise.resolve(new Response("{}", { status: 500 }));
  }) as typeof fetch;

  try {
    const storage = createProfilePhotoStorage(
      "https://project.supabase.co",
      "service-role-key",
    );

    const first = await storage.createSignedUrl(objectPath);
    const second = await storage.createSignedUrl(objectPath);

    assertEquals(first, second);
    assertEquals(bucketReads, 1);
    assertEquals(signRequests, 1);

    await storage.remove(objectPath);
    const afterDelete = await storage.createSignedUrl(objectPath);

    assertEquals(deletes, 1);
    assertEquals(signRequests, 2);
    assertEquals(afterDelete.includes("token=2"), true);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

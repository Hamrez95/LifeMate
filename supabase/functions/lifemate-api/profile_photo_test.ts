import { assert, assertEquals, assertThrows } from "jsr:@std/assert@1.0.14";
import { ApiError } from "./validation.ts";
import {
  createProfilePhotoStorage,
  profilePhotoMaximumBytes,
  validateProfilePhoto,
} from "./profile_photo.ts";

Deno.test("profile photo validation accepts matching JPEG PNG and WebP signatures", () => {
  assertEquals(
    validateProfilePhoto(
      new Uint8Array([0xff, 0xd8, 0xff, 0x00]),
      "image/jpeg",
    ),
    { contentType: "image/jpeg", extension: "jpg" },
  );
  assertEquals(
    validateProfilePhoto(
      new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
      "image/png; charset=binary",
    ),
    { contentType: "image/png", extension: "png" },
  );
  assertEquals(
    validateProfilePhoto(
      new Uint8Array([
        0x52,
        0x49,
        0x46,
        0x46,
        0,
        0,
        0,
        0,
        0x57,
        0x45,
        0x42,
        0x50,
      ]),
      "image/webp",
    ),
    { contentType: "image/webp", extension: "webp" },
  );
});

Deno.test("profile photo validation rejects spoofed and oversized payloads", () => {
  const spoofed = assertThrows(
    () => validateProfilePhoto(new Uint8Array([1, 2, 3]), "image/jpeg"),
    ApiError,
  );
  assertEquals(spoofed.code, "invalid_profile_photo");
  assertEquals(spoofed.status, 415);

  const oversized = assertThrows(
    () =>
      validateProfilePhoto(
        new Uint8Array(profilePhotoMaximumBytes + 1),
        "image/png",
      ),
    ApiError,
  );
  assertEquals(oversized.code, "profile_photo_too_large");
  assertEquals(oversized.status, 413);
});


Deno.test("profile photo storage creates a private bucket when hosted Storage returns 400 for missing bucket", async () => {
  const originalFetch = globalThis.fetch;
  const calls: Array<{ method: string; url: string }> = [];
  globalThis.fetch = ((input: string | URL | Request, init?: RequestInit) => {
    const url = input.toString();
    const method = init?.method ?? "GET";
    calls.push({ method, url });
    if (method === "GET" && url.endsWith("/storage/v1/bucket/profile-photos")) {
      return Promise.resolve(new Response('{"message":"Bucket not found"}', { status: 400 }));
    }
    if (method === "POST" && url.endsWith("/storage/v1/bucket")) {
      return Promise.resolve(new Response('{}', { status: 200 }));
    }
    if (method === "POST" && url.includes("/storage/v1/object/profile-photos/")) {
      return Promise.resolve(new Response('{}', { status: 200 }));
    }
    return Promise.resolve(new Response('{}', { status: 500 }));
  }) as typeof fetch;
  try {
    const storage = createProfilePhotoStorage(
      "https://project.supabase.co",
      "service-role-key",
    );
    const path = await storage.upload(
      "01805aff-0a88-49ce-b676-b914646c2072",
      new Uint8Array([0xff, 0xd8, 0xff, 0x00]),
      "image/jpeg",
    );
    assert(path.endsWith(".jpg"));
    assertEquals(calls[0].method, "GET");
    assertEquals(calls[1].method, "POST");
    assertEquals(calls[2].method, "POST");
  } finally {
    globalThis.fetch = originalFetch;
  }
});

import { assertEquals, assertThrows } from "jsr:@std/assert@1";
import { ApiError } from "./validation.ts";
import { decodeSyncCursor, encodeSyncCursor } from "./care_event_sync.ts";

Deno.test("care-event sync cursor round-trips deterministically", () => {
  const cursor = {
    updatedAtUtc: "2026-09-05T01:02:03.456Z",
    id: "123e4567-e89b-42d3-a456-426614174000",
  };
  const encoded = encodeSyncCursor(cursor);
  assertEquals(encoded.startsWith("v1."), true);
  assertEquals(encoded.includes(cursor.id), false);
  assertEquals(decodeSyncCursor(encoded), cursor);
});

Deno.test("empty care-event sync cursor resolves to stable origin", () => {
  assertEquals(decodeSyncCursor(null), {
    updatedAtUtc: "1970-01-01T00:00:00.000Z",
    id: "00000000-0000-1000-8000-000000000000",
  });
});

Deno.test("invalid care-event sync cursor fails closed", () => {
  const error = assertThrows(
    () => decodeSyncCursor("v1.not-valid-base64"),
    ApiError,
  );
  assertEquals(error.status, 400);
  assertEquals(error.code, "invalid_sync_cursor");
});

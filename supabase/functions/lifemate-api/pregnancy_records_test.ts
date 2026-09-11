import { assertEquals } from "jsr:@std/assert@1.0.14";
import {
  decodePregnancyRecordsCursor,
  encodePregnancyRecordsCursor,
  paginatePregnancyRecords,
  type PregnancyRecordItem,
} from "./pregnancy_records.ts";

function record(id: string, occurredAtUtc: string): PregnancyRecordItem {
  return {
    id,
    sourceKind: "test",
    sourceId: id,
    category: "check_ins",
    occurredAtUtc,
    localDate: occurredAtUtc.slice(0, 10),
    type: "test",
    summary: {},
  };
}

Deno.test("pregnancy records cursor round-trips only the stable ordering key", () => {
  const value = record("checkin:1", "2026-09-11T09:30:00.000Z");
  assertEquals(decodePregnancyRecordsCursor(encodePregnancyRecordsCursor(value)), {
    occurredAtUtc: value.occurredAtUtc,
    id: value.id,
  });
});

Deno.test("pregnancy records rejects malformed cursors without throwing", () => {
  for (const value of [
    null,
    "",
    "not-base64-json",
    btoa("{}"),
    btoa(JSON.stringify({ occurredAtUtc: "2026-09-11T00:00:00.000Z" })),
    btoa(JSON.stringify({ id: "checkin:1" })),
  ]) {
    assertEquals(decodePregnancyRecordsCursor(value), null);
  }
});

Deno.test("pregnancy records pagination is deterministic for timestamp ties", () => {
  const values = [
    record("a", "2026-09-11T10:00:00.000Z"),
    record("c", "2026-09-11T10:00:00.000Z"),
    record("b", "2026-09-11T10:00:00.000Z"),
  ];
  const first = paginatePregnancyRecords(values, 2, null);
  assertEquals(first.items.map((item) => item.id), ["c", "b"]);
  const cursor = decodePregnancyRecordsCursor(first.nextCursor);
  assertEquals(cursor, {
    occurredAtUtc: "2026-09-11T10:00:00.000Z",
    id: "b",
  });
  const second = paginatePregnancyRecords(values, 2, cursor);
  assertEquals(second.items.map((item) => item.id), ["a"]);
  assertEquals(second.nextCursor, null);
});

Deno.test("pregnancy records cursor remains stable when newer items arrive", () => {
  const initial = [
    record("a", "2026-09-12T10:00:00.000Z"),
    record("b", "2026-09-11T10:00:00.000Z"),
    record("c", "2026-09-10T10:00:00.000Z"),
  ];
  const first = paginatePregnancyRecords(initial, 2, null);
  const cursor = decodePregnancyRecordsCursor(first.nextCursor);
  const newer = record("new", "2026-09-13T10:00:00.000Z");
  const second = paginatePregnancyRecords([...initial, newer], 2, cursor);
  assertEquals(second.items.map((item) => item.id), ["c"]);
  assertEquals(second.nextCursor, null);
});

Deno.test("pregnancy records empty input returns a truthful empty page", () => {
  assertEquals(paginatePregnancyRecords([], 30, null), {
    items: [],
    nextCursor: null,
  });
});

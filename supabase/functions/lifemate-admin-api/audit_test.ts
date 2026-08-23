import { assertEquals } from "jsr:@std/assert@1";

import {
  decodeAuditCursor,
  encodeAuditCursor,
  parseAuditQuery,
} from "./audit.ts";
import { ApiError } from "./validation.ts";

Deno.test("audit query defaults are bounded", () => {
  const query = parseAuditQuery(new URL("https://admin.test/api/v1/audit"));
  assertEquals(query, {
    limit: 50,
    fromUtc: null,
    toUtc: null,
    cursor: null,
  });
});

Deno.test("audit query normalizes date range and limit", () => {
  const query = parseAuditQuery(
    new URL(
      "https://admin.test/api/v1/audit?limit=100&from=2026-08-01T10:30:00%2B03:30&to=2026-08-23T23:59:59Z",
    ),
  );
  assertEquals(query.limit, 100);
  assertEquals(query.fromUtc, "2026-08-01T07:00:00.000Z");
  assertEquals(query.toUtc, "2026-08-23T23:59:59.000Z");
});

Deno.test("audit cursor round trips stable ordering tuple", () => {
  const cursor = {
    occurredAtUtc: "2026-08-23T09:51:52.000Z",
    id: "123e4567-e89b-42d3-a456-426614174000",
  };
  assertEquals(decodeAuditCursor(encodeAuditCursor(cursor)), cursor);
});

Deno.test("audit query rejects inverted date ranges", () => {
  let thrown: unknown;
  try {
    parseAuditQuery(
      new URL(
        "https://admin.test/api/v1/audit?from=2026-08-24T00:00:00Z&to=2026-08-23T00:00:00Z",
      ),
    );
  } catch (error) {
    thrown = error;
  }
  if (!(thrown instanceof ApiError)) throw new Error("expected ApiError");
  assertEquals(thrown.status, 400);
  assertEquals(thrown.code, "audit_range_invalid");
});

Deno.test("audit query rejects malformed cursor", () => {
  let thrown: unknown;
  try {
    parseAuditQuery(
      new URL("https://admin.test/api/v1/audit?cursor=not-a-valid-cursor"),
    );
  } catch (error) {
    thrown = error;
  }
  if (!(thrown instanceof ApiError)) throw new Error("expected ApiError");
  assertEquals(thrown.status, 400);
  assertEquals(thrown.code, "audit_cursor_invalid");
});

Deno.test("audit query rejects unbounded page sizes", () => {
  let thrown: unknown;
  try {
    parseAuditQuery(new URL("https://admin.test/api/v1/audit?limit=101"));
  } catch (error) {
    thrown = error;
  }
  if (!(thrown instanceof ApiError)) throw new Error("expected ApiError");
  assertEquals(thrown.status, 400);
});

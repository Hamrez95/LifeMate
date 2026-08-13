import { assertEquals, assertRejects } from "jsr:@std/assert";

import { ApiError } from "./validation.ts";
import { parseUserDirectoryQuery } from "./directory.ts";

Deno.test("user directory defaults are bounded", () => {
  const query = parseUserDirectoryQuery(new URL("https://example.test/api/v1/users"));
  assertEquals(query, {
    page: 1,
    pageSize: 25,
    offset: 0,
    search: null,
    status: null,
    application: null,
    sort: "createdAt",
    direction: "desc",
  });
});

Deno.test("user directory accepts approved filters and sort", () => {
  const query = parseUserDirectoryQuery(
    new URL(
      "https://example.test/api/v1/users?page=2&pageSize=50&q=Sara&status=Active&application=wellmate&sort=displayName&direction=asc",
    ),
  );
  assertEquals(query.page, 2);
  assertEquals(query.pageSize, 50);
  assertEquals(query.offset, 50);
  assertEquals(query.search, "Sara");
  assertEquals(query.status, "Active");
  assertEquals(query.application, "wellmate");
  assertEquals(query.sort, "displayName");
  assertEquals(query.direction, "asc");
});

Deno.test("user directory rejects unsafe or unbounded query values", async () => {
  for (const url of [
    "https://example.test/api/v1/users?pageSize=101",
    "https://example.test/api/v1/users?q=x",
    "https://example.test/api/v1/users?status=Unknown",
    "https://example.test/api/v1/users?application=bad%20value",
    "https://example.test/api/v1/users?sort=contact",
    "https://example.test/api/v1/users?direction=sideways",
  ]) {
    await assertRejects(
      async () => parseUserDirectoryQuery(new URL(url)),
      ApiError,
    );
  }
});

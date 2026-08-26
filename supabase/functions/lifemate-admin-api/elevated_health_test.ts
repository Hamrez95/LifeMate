import { assertEquals, assertRejects } from "jsr:@std/assert";

import { parseElevatedHealthQuery } from "./elevated_health.ts";

Deno.test("elevated health route requires exact subject and capability", () => {
  const subject = "11111111-1111-4111-8111-111111111111";
  const query = parseElevatedHealthQuery(
    new URL(
      `https://admin.test/api/v1/security/elevated-health/${subject}?capability=health.read.elevated&limit=25`,
    ),
  );
  assertEquals(query, {
    subjectPersonId: subject,
    capability: "health.read.elevated",
    limit: 25,
  });
});

Deno.test("elevated health route rejects missing or invented capabilities", () => {
  const subject = "11111111-1111-4111-8111-111111111111";
  assertRejects(
    () =>
      Promise.resolve(
        parseElevatedHealthQuery(
          new URL(
            `https://admin.test/api/v1/security/elevated-health/${subject}?capability=health.read.all`,
          ),
        ),
      ),
    Error,
    "exact elevated health capability",
  );
});

Deno.test("elevated health page size is bounded", () => {
  const subject = "11111111-1111-4111-8111-111111111111";
  assertRejects(
    () =>
      Promise.resolve(
        parseElevatedHealthQuery(
          new URL(
            `https://admin.test/api/v1/security/elevated-health/${subject}?capability=women_health.read.elevated&limit=500`,
          ),
        ),
      ),
    Error,
    "between 1 and 50",
  );
});

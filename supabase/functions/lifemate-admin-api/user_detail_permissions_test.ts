import { assertEquals } from "jsr:@std/assert";

import { getUserDetailSectionPermissions } from "./user_detail_permissions.ts";

Deno.test("User 360 optional sections require their own permissions", () => {
  assertEquals(getUserDetailSectionPermissions(["users.read.basic"]), {
    commerce: false,
    relationships: false,
    adminActivity: false,
  });

  assertEquals(
    getUserDetailSectionPermissions([
      "users.read.basic",
      "commerce.read",
      "relationships.read",
      "security.audit.read",
    ]),
    {
      commerce: true,
      relationships: true,
      adminActivity: true,
    },
  );
});

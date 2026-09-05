import {
  assert,
  assertFalse,
  assertStringIncludes,
} from "jsr:@std/assert@1.0.14";

Deno.test("Admin support visible-message routes stay permissioned and audited", async () => {
  const routes = await Deno.readTextFile(
    new URL("./support_conversation_routes.ts", import.meta.url),
  );
  const migration = await Deno.readTextFile(
    new URL(
      "../../migrations/20260827112100_support_staff_visible_messages.sql",
      import.meta.url,
    ),
  );
  const executableMigration = migration.replace(/--.*$/gm, "");
  const dispatcher = await Deno.readTextFile(
    new URL("./staff_directory_routes.ts", import.meta.url),
  );

  assertStringIncludes(routes, 'requirePermission(admin, "support.read")');
  assertStringIncludes(routes, 'requirePermission(admin, "support.write")');
  assertStringIncludes(routes, "requireIdempotencyKey(request)");
  assertStringIncludes(migration, "admin.send_support_conversation_message");
  assertStringIncludes(migration, "support.conversation.message.sent");
  assert(
    /supportConversationRouteHandler\(\s*input,?\s*\)/.test(dispatcher),
    "canonical staff dispatcher must forward authenticated context to support conversations",
  );

  // Visible conversation messages are distinct from privacy-minimized internal
  // notes. Ignore explanatory SQL comments and guard executable statements.
  assertFalse(executableMigration.includes("jsonb_build_object('body'"));
  assertFalse(executableMigration.includes("InternalNoteAdded"));
});

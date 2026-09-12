import {
  assertFalse,
  assertStringIncludes,
} from "jsr:@std/assert@1.0.14";

Deno.test("Admin support visible-message routes stay permissioned and audited", async () => {
  const routes = await Deno.readTextFile(
    new URL("./support_conversation_routes.ts", import.meta.url),
  );
  const messageMigration = await Deno.readTextFile(
    new URL(
      "../../migrations/20260827112100_support_staff_visible_messages.sql",
      import.meta.url,
    ),
  );
  const operationMigration = await Deno.readTextFile(
    new URL(
      "../../migrations/20260827220500_support_admin_operation_idempotency.sql",
      import.meta.url,
    ),
  );
  const dispatcher = await Deno.readTextFile(
    new URL("./staff_directory_routes.ts", import.meta.url),
  );

  assertStringIncludes(routes, 'requirePermission(admin, "support.read")');
  assertStringIncludes(routes, 'requirePermission(admin, "support.write")');
  assertStringIncludes(routes, "requireIdempotencyKey(request)");
  assertStringIncludes(routes, "/conversation\\/operations");
  assertStringIncludes(routes, "/conversation\\/escalations");
  assertStringIncludes(routes, "/conversation\\/links");
  assertStringIncludes(messageMigration, "admin.send_support_conversation_message");
  assertStringIncludes(messageMigration, "support.conversation.message.sent");
  assertStringIncludes(dispatcher, "supportConversationRouteHandler(input)");

  assertStringIncludes(operationMigration, "admin.idempotency_keys");
  assertStringIncludes(operationMigration, "support.escalation.create");
  assertStringIncludes(operationMigration, "support.reference.link");
  assertStringIncludes(operationMigration, "idempotency_conflict");
  assertStringIncludes(operationMigration, "operation_in_progress");
  assertStringIncludes(operationMigration, "admin.create_support_escalation(");
  assertStringIncludes(operationMigration, "admin.link_support_ticket_reference(");

  assertFalse(messageMigration.includes("jsonb_build_object('body'"));
  assertFalse(messageMigration.includes("InternalNoteAdded"));
  assertFalse(operationMigration.includes("response_json=v_response ||"));
  assertFalse(operationMigration.includes("healthPayload"));
});

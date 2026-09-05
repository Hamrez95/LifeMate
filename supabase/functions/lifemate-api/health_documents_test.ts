import { assertEquals, assertThrows } from "jsr:@std/assert@1.0.14";
import { parseHealthDocumentLink } from "./health_documents.ts";
import { ApiError } from "./validation.ts";

const uuid = "018f5e6a-7e91-4c26-8e18-a83c5531d111";

Deno.test("Health Record form links accept only complete, known contexts", () => {
  assertEquals(parseHealthDocumentLink(null, null), null);
  assertEquals(parseHealthDocumentLink("care_event", uuid), {
    contextType: "care_event",
    contextId: uuid,
  });
  assertEquals(parseHealthDocumentLink("treatment_plan", uuid), {
    contextType: "treatment_plan",
    contextId: uuid,
  });
  const incomplete = assertThrows(() =>
    parseHealthDocumentLink("care_event", null)
  );
  assertEquals(incomplete instanceof ApiError, true);
  assertEquals(
    (incomplete as ApiError).code,
    "health_document_link_invalid",
  );
  assertThrows(() => parseHealthDocumentLink("appointment", uuid));
  assertThrows(() => parseHealthDocumentLink("care_event", "not-a-uuid"));
});

import { assertEquals, assertThrows } from "jsr:@std/assert@1.0.14";
import { parseFeedbackSubmission } from "./feedback.ts";
import { ApiError } from "./validation.ts";
Deno.test("feedback accepts bounded structured bug report metadata", () => {
  assertEquals(
    parseFeedbackSubmission({
      kind: "BugReport",
      productCode: "wellmate",
      appVersion: "1.2.3",
      buildNumber: "42",
      message: "The save action failed after reconnect.",
    }),
    {
      kind: "BugReport",
      productCode: "wellmate",
      appVersion: "1.2.3",
      buildNumber: "42",
      npsScore: null,
      message: "The save action failed after reconnect.",
      advocacyOptIn: false,
    },
  );
});
Deno.test("NPS accepts only integer scores zero through ten", () => {
  assertEquals(
    parseFeedbackSubmission({
      kind: "Nps",
      productCode: "caremate",
      npsScore: 10,
    }).npsScore,
    10,
  );
  for (const npsScore of [-1, 11, 8.5, "10"]) {
    assertThrows(() =>
      parseFeedbackSubmission({
        kind: "Nps",
        productCode: "caremate",
        npsScore,
      }), ApiError);
  }
});
Deno.test("advocacy requires explicit opt-in and rejects hidden evidence", () => {
  assertThrows(
    () =>
      parseFeedbackSubmission({
        kind: "Advocacy",
        productCode: "wellmate",
        message: "Shared LifeMate.",
      }),
    ApiError,
  );
  const error = assertThrows(
    () =>
      parseFeedbackSubmission({
        kind: "Advocacy",
        productCode: "wellmate",
        message: "Shared LifeMate.",
        advocacyOptIn: true,
        socialProfile: "hidden",
      }),
    ApiError,
  );
  assertEquals(error.code, "feedback_field_forbidden");
});
Deno.test("ordinary feedback cannot carry advocacy consent", () => {
  const error = assertThrows(
    () =>
      parseFeedbackSubmission({
        kind: "Feedback",
        productCode: "wellmate",
        message: "Useful app",
        advocacyOptIn: true,
      }),
    ApiError,
  );
  assertEquals(error.code, "feedback_advocacy_opt_in_forbidden");
});

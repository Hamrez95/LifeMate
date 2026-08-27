import { assertEquals, assertThrows } from "jsr:@std/assert@1.0.14";
import { parseFeedbackSubmission } from "./feedback.ts";
import { ApiError } from "./validation.ts";

Deno.test("feedback accepts bounded structured bug report metadata", () => {
  assertEquals(parseFeedbackSubmission({
    kind: "BugReport",
    productCode: "wellmate",
    appVersion: "1.2.3",
    buildNumber: "42",
    message: "The save action failed after reconnect.",
  }), {
    kind: "BugReport",
    productCode: "wellmate",
    appVersion: "1.2.3",
    buildNumber: "42",
    npsScore: null,
    message: "The save action failed after reconnect.",
    advocacyOptIn: false,
  });
});

Deno.test("NPS accepts only integer scores from zero through ten", () => {
  assertEquals(parseFeedbackSubmission({
    kind: "Nps",
    productCode: "caremate",
    npsScore: 10,
  }).npsScore, 10);

  for (const npsScore of [-1, 11, 8.5, "10"]) {
    const error = assertThrows(() => parseFeedbackSubmission({
      kind: "Nps",
      productCode: "caremate",
      npsScore,
    }), ApiError);
    assertEquals(error.code, "feedback_nps_score_invalid");
  }
});

Deno.test("non-NPS feedback requires meaningful text and rejects scores", () => {
  let error = assertThrows(() => parseFeedbackSubmission({
    kind: "Feedback",
    productCode: "wellmate",
  }), ApiError);
  assertEquals(error.code, "feedback_message_required");

  error = assertThrows(() => parseFeedbackSubmission({
    kind: "Feedback",
    productCode: "wellmate",
    message: "Useful feedback",
    npsScore: 7,
  }), ApiError);
  assertEquals(error.code, "feedback_nps_score_forbidden");
});

Deno.test("advocacy is explicit opt-in and rejects hidden evidence fields", () => {
  let error = assertThrows(() => parseFeedbackSubmission({
    kind: "Advocacy",
    productCode: "wellmate",
    message: "I mentioned LifeMate in my story.",
  }), ApiError);
  assertEquals(error.code, "feedback_advocacy_opt_in_required");

  error = assertThrows(() => parseFeedbackSubmission({
    kind: "Advocacy",
    productCode: "wellmate",
    message: "I mentioned LifeMate in my story.",
    advocacyOptIn: true,
    socialProfile: "private-profile",
  }), ApiError);
  assertEquals(error.code, "feedback_field_forbidden");
});

Deno.test("feedback rejects oversized text and unsupported product metadata", () => {
  let error = assertThrows(() => parseFeedbackSubmission({
    kind: "FeatureRequest",
    productCode: "wellmate",
    message: "x".repeat(2001),
  }), ApiError);
  assertEquals(error.code, "feedback_text_invalid");

  error = assertThrows(() => parseFeedbackSubmission({
    kind: "Feedback",
    productCode: "../unsafe",
    message: "Unsafe product",
  }), ApiError);
  assertEquals(error.code, "feedback_product_invalid");
});

import { createFeedbackStore, parseFeedbackSubmission } from "./feedback.ts";
import { requireMutationIdempotencyKey } from "./idempotency.ts";
import { json } from "./http.ts";
import { enforceRateLimit } from "./security.ts";
import { ApiError, readJsonObject } from "./validation.ts";
export function createFeedbackRouteHandler(databaseUrl: string) {
  const store = createFeedbackStore(databaseUrl);
  return async function feedbackRouteHandler(
    input: { request: Request; path: string; appUserId: string },
  ): Promise<Response | null> {
    const { request, path, appUserId } = input;
    if (request.method !== "POST" || path !== "/api/v1/feedback") return null;
    enforceRateLimit(`feedback:${appUserId}`, 12, 60 * 60_000);
    const body = await readJsonObject(request);
    if ("attachment" in body || "attachmentUrl" in body || "file" in body) {
      throw new ApiError(
        400,
        "feedback_attachment_path_required",
        "Feedback attachments must use the reviewed secure attachment flow.",
      );
    }
    return json(
      await store.submit(
        appUserId,
        parseFeedbackSubmission(body),
        requireMutationIdempotencyKey(request),
      ),
      201,
    );
  };
}

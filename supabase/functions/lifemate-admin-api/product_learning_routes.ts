import type { AdminCapabilitySnapshot } from "./authorization.ts";
import { createExperimentRouteHandler } from "./experiments_routes.ts";
import { createFeedbackAdminRouteHandler } from "./feedback_admin_routes.ts";

export function createProductLearningRouteHandler(databaseUrl: string) {
  const experimentRouteHandler = createExperimentRouteHandler(databaseUrl);
  const feedbackRouteHandler = createFeedbackAdminRouteHandler(databaseUrl);

  return async function productLearningRouteHandler(input: {
    request: Request;
    path: string;
    accountId: string;
    admin: AdminCapabilitySnapshot;
    correlationId: string;
    origin: string | null;
  }): Promise<Response | null> {
    const experimentResponse = await experimentRouteHandler(input);
    if (experimentResponse) return experimentResponse;
    return feedbackRouteHandler(input);
  };
}

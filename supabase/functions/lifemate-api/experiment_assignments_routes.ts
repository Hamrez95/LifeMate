import {
  createExperimentAssignmentStore,
  parseExperimentAssignmentProduct,
} from "./experiment_assignments.ts";
import { json } from "./http.ts";
import { enforceRateLimit } from "./security.ts";
import { ApiError, readJsonObject } from "./validation.ts";

export function createExperimentAssignmentRouteHandler(
  databaseUrl: string,
  hashingSecret: string,
) {
  const store = createExperimentAssignmentStore(databaseUrl, hashingSecret);
  return async function experimentAssignmentRouteHandler(input: {
    request: Request;
    path: string;
    appUserId: string;
  }): Promise<Response | null> {
    if (
      input.request.method !== "POST" ||
      input.path !== "/api/v1/experiments/assignments"
    ) {
      return null;
    }
    enforceRateLimit(
      `experiment-assignment:${input.appUserId}`,
      30,
      60 * 60_000,
    );
    const body = await readJsonObject(input.request);
    if (Object.keys(body).some((key) => key !== "product")) {
      throw new ApiError(
        400,
        "experiment_assignment_field_forbidden",
        "Experiment assignment payload contains an unsupported field.",
      );
    }
    const product = parseExperimentAssignmentProduct(body.product);
    return json(await store.assignAndRecord(input.appUserId, product));
  };
}

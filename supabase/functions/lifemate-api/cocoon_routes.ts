import { createCocoonApplicationBoundary } from "./cocoon_application.ts";
import { json } from "./http.ts";
import { createPregnancyRouteHandler } from "./pregnancy_routes.ts";
import { ApiError } from "./validation.ts";

type Row = Record<string, unknown>;

export function createCocoonRouteHandler(databaseUrl: string) {
  const application = createCocoonApplicationBoundary(databaseUrl);
  const pregnancy = createPregnancyRouteHandler(databaseUrl);

  return async ({
    request,
    path,
    appUserId,
  }: {
    request: Request;
    path: string;
    appUserId: string;
  }): Promise<Response | null> => {
    if (!path.startsWith("/api/v1/cocoon/")) return null;

    const applicationState = await application.resolveAndEnroll(appUserId);
    if (applicationState.availability !== "available") {
      throw new ApiError(
        503,
        "cocoon_application_unavailable",
        "CocoonMate is currently unavailable.",
      );
    }
    if (applicationState.enrollmentState !== "active") {
      throw new ApiError(
        403,
        "cocoon_application_enrollment_inactive",
        "CocoonMate enrollment is not active.",
      );
    }

    const response = await pregnancy({ request, path, appUserId });
    if (!response) return null;
    if (request.method !== "GET" || path !== "/api/v1/cocoon/bootstrap") {
      return response;
    }

    const body = await response.json() as Row;
    const commerceEligibility = await application.commerceEligibility(
      appUserId,
    );
    return json({
      ...body,
      // `enrollmentState` remains the frozen v1 pregnancy lifecycle field.
      // Application enrollment is additive and independently typed.
      applicationState,
      experienceEligibility: {
        state: "eligible",
      },
      commerceEligibility,
    }, response.status);
  };
}

import {
  type CocoonCommerceEligibilitySnapshot,
  createCocoonApplicationBoundary,
} from "./cocoon_application.ts";
import { json } from "./http.ts";
import { createPregnancyCalendarRouteHandler } from "./pregnancy_calendar.ts";
import { createPregnancyRouteHandler } from "./pregnancy_routes.ts";
import { ApiError } from "./validation.ts";

type Row = Record<string, unknown>;

export function requiresCocoonPregnancyActivationEntitlement(
  method: string,
  path: string,
): boolean {
  if (method !== "POST") return false;
  if (path === "/api/v1/cocoon/pregnancy/episodes") return true;
  return /^\/api\/v1\/cocoon\/pregnancy\/episodes\/[0-9a-f-]{36}\/activate$/i
    .test(path);
}

export function requireCocoonPregnancyActivationEntitlement(
  commerce: CocoonCommerceEligibilitySnapshot,
): void {
  if (commerce.state === "entitled") return;
  if (commerce.state === "error") {
    throw new ApiError(
      503,
      "cocoon_commerce_unavailable",
      "CocoonMate subscription state is temporarily unavailable.",
    );
  }
  if (commerce.state === "unavailable") {
    throw new ApiError(
      503,
      "cocoon_product_unavailable",
      "CocoonMate is currently unavailable.",
    );
  }
  throw new ApiError(
    403,
    "cocoon_entitlement_required",
    "An active CocoonMate entitlement is required for pregnancy activation.",
  );
}

export function createCocoonRouteHandler(databaseUrl: string) {
  const application = createCocoonApplicationBoundary(databaseUrl);
  const pregnancy = createPregnancyRouteHandler(databaseUrl);
  const pregnancyCalendar = createPregnancyCalendarRouteHandler(databaseUrl);

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

    let commerceEligibility: CocoonCommerceEligibilitySnapshot | null = null;
    if (
      requiresCocoonPregnancyActivationEntitlement(request.method, path)
    ) {
      commerceEligibility = await application.commerceEligibility(appUserId);
      requireCocoonPregnancyActivationEntitlement(commerceEligibility);
    }

    const calendarResponse = await pregnancyCalendar({
      request,
      path,
      appUserId,
    });
    if (calendarResponse) return calendarResponse;

    const response = await pregnancy({ request, path, appUserId });
    if (!response) return null;
    if (request.method !== "GET" || path !== "/api/v1/cocoon/bootstrap") {
      return response;
    }

    const body = await response.json() as Row;
    commerceEligibility ??= await application.commerceEligibility(appUserId);
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

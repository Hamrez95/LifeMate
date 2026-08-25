import type { AdminCapabilitySnapshot } from "./authorization.ts";
import { requirePermission } from "./authorization.ts";
import {
  advisorKpiQuery,
  assertAdvisorSourcePermissions,
  buildAdvisorInsight,
  parseAdvisorRequest,
  safeAdvisorLogFields,
} from "./advisor.ts";
import { createAnalyticsKpiStore } from "./analytics_kpi_service.ts";
import { buildDailyBrief } from "./daily_brief.ts";
import { json } from "./http.ts";

export type AdvisorRouteContext = {
  request: Request;
  path: string;
  accountId: string;
  admin: AdminCapabilitySnapshot;
  correlationId: string;
  origin: string | null;
};

export function createAdvisorRouteHandler(databaseUrl: string) {
  const analytics = createAnalyticsKpiStore(databaseUrl);

  return async function handleAdvisorRoute(
    context: AdvisorRouteContext,
  ): Promise<Response | null> {
    const { request, path, admin, correlationId, origin } = context;

    if (request.method === "GET" && path === "/api/v1/ai/daily-brief") {
      requirePermission(admin, "ai.business.read");
      requirePermission(admin, "analytics.read");
      const values = await analytics.getValues(advisorKpiQuery());
      const brief = buildDailyBrief(values, new Date().toISOString());
      console.info("LifeMate read-only Daily Brief generated", {
        correlationId,
        state: brief.state,
        evidenceCount: brief.evidence.length,
        changesCount: brief.changes.length,
        attentionCount: brief.attention.length,
      });
      return json(
        {
          ...brief,
          sourcePolicy: {
            mode: "deterministic",
            approvedReadModelsOnly: true,
            rawHealthData: false,
            medicalAdvice: false,
            mutations: false,
          },
        },
        200,
        origin,
      );
    }

    if (
      request.method !== "POST" ||
      path !== "/api/v1/ai/advisor/insights"
    ) {
      return null;
    }

    requirePermission(admin, "ai.advisor.read");
    const advisorRequest = await parseAdvisorRequest(request);
    assertAdvisorSourcePermissions(admin, advisorRequest.topic);

    // The question is deliberately not interpolated into SQL, prompts, URLs, or
    // connector calls. It is untrusted context only. Topic selection is an
    // allowlisted enum and therefore fully determines which read models execute.
    const values = await analytics.getValues(advisorKpiQuery());
    const generatedAtUtc = new Date().toISOString();
    const insight = buildAdvisorInsight(
      advisorRequest.topic,
      values,
      generatedAtUtc,
    );

    console.info("LifeMate read-only advisor request completed", {
      correlationId,
      ...safeAdvisorLogFields(advisorRequest),
      evidenceCount: insight.evidence.length,
      mode: insight.mode,
    });

    return json(
      {
        ...insight,
        model: {
          status: "not_configured",
          fallbackUsed: true,
          note:
            "Phase 1 uses the deterministic grounded advisor so model availability cannot remove source/freshness evidence.",
        },
      },
      200,
      origin,
    );
  };
}

import { createCocoonIdentityResolver } from "./cocoon_identity.ts";
import { json } from "./http.ts";
import { createPersonDoseOccurrenceStore } from "./person_dose_occurrences.ts";
import { createPersonTreatmentPlanStore } from "./person_treatment_plans.ts";
import { createPregnancyAuthorization } from "./pregnancy_authorization.ts";
import { createPregnancyStore } from "./pregnancy_store.ts";
import { ApiError, requiredDate, validateRange } from "./validation.ts";

type Row = Record<string, unknown>;

type PregnancyTreatmentDependencies = {
  resolveIdentity: (appUserId: string) => Promise<{
    accountId: string;
    personId: string;
  }>;
  currentEpisode: (personId: string) => Promise<Row | null>;
  requireMedicationRead: (args: {
    callerAccountId: string;
    subjectPersonId: string;
    episodeId: string;
  }) => Promise<void>;
  listTreatmentPlans: (appUserId: string) => Promise<Row[]>;
  listDoseOccurrences: (
    appUserId: string,
    fromDate: string,
    toDate: string,
  ) => Promise<Row[]>;
};

function defaultDependencies(
  databaseUrl: string,
): PregnancyTreatmentDependencies {
  const identity = createCocoonIdentityResolver(databaseUrl);
  const pregnancy = createPregnancyStore(databaseUrl);
  const authorization = createPregnancyAuthorization(databaseUrl);
  const treatments = createPersonTreatmentPlanStore(databaseUrl);
  const doses = createPersonDoseOccurrenceStore(databaseUrl);
  return {
    resolveIdentity: identity.resolve,
    currentEpisode: pregnancy.getCurrentEpisode,
    requireMedicationRead: (args) =>
      authorization.requireAccess({
        callerAccountId: args.callerAccountId,
        subjectPersonId: args.subjectPersonId,
        episodeId: args.episodeId,
        scope: "pregnancy.medications.read",
      }),
    listTreatmentPlans: treatments.listTreatmentPlans,
    listDoseOccurrences: doses.listDoseOccurrences,
  };
}

function planId(value: Row): string {
  return typeof value.id === "string" ? value.id : "";
}

function isActivePlan(value: Row): boolean {
  return String(value.status ?? "").toLowerCase() === "active";
}

export function createPregnancyTreatmentRouteHandler(
  databaseUrl: string,
  dependencies: PregnancyTreatmentDependencies = defaultDependencies(
    databaseUrl,
  ),
) {
  async function context(appUserId: string) {
    const { accountId, personId } = await dependencies.resolveIdentity(
      appUserId,
    );
    const episode = await dependencies.currentEpisode(personId);
    if (!episode || String(episode.status ?? "").toLowerCase() !== "active") {
      throw new ApiError(
        409,
        "active_pregnancy_required",
        "An active pregnancy is required.",
      );
    }
    const episodeId = String(episode.id ?? "");
    if (!episodeId) {
      throw new ApiError(
        409,
        "active_pregnancy_required",
        "An active pregnancy is required.",
      );
    }
    await dependencies.requireMedicationRead({
      callerAccountId: accountId,
      subjectPersonId: personId,
      episodeId,
    });
    return { episodeId };
  }

  return async ({
    request,
    path,
    appUserId,
  }: {
    request: Request;
    path: string;
    appUserId: string;
  }): Promise<Response | null> => {
    if (
      request.method !== "GET" ||
      path !== "/api/v1/cocoon/pregnancy/treatments"
    ) {
      return null;
    }

    const url = new URL(request.url);
    const fromDate = requiredDate(url.searchParams.get("fromDate"), "fromDate");
    const toDate = requiredDate(url.searchParams.get("toDate"), "toDate");
    validateRange(fromDate, toDate, 31);

    const { episodeId } = await context(appUserId);
    const [plans, occurrences] = await Promise.all([
      dependencies.listTreatmentPlans(appUserId),
      dependencies.listDoseOccurrences(appUserId, fromDate, toDate),
    ]);
    const activePlans = plans.filter(isActivePlan);
    const activePlanIds = new Set(activePlans.map(planId).filter(Boolean));
    const activeOccurrences = occurrences.filter((occurrence) => {
      const treatmentPlanId = occurrence.treatmentPlanId;
      return typeof treatmentPlanId === "string" &&
        activePlanIds.has(treatmentPlanId);
    });

    return json({
      contractVersion: 1,
      episodeId,
      fromDate,
      toDate,
      treatmentPlans: activePlans,
      doseOccurrences: activeOccurrences,
      mutationAuthority: "canonical_treatment_api",
    });
  };
}

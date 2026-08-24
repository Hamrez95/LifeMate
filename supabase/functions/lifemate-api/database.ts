export * from "./database_legacy.ts";

import { rawContactRetirementEnabled } from "./contact_points.ts";
import {
  createLifeMateDatabase as createLegacyLifeMateDatabase,
} from "./database_legacy.ts";
import { createIdentityResolver } from "./identity_resolver.ts";
import { createInvitationRevocationStore } from "./invitation_revoke.ts";
import { createPersonCareRelationshipManagementStore } from "./person_care_relationship_management.ts";
import { createPersonDoseOccurrenceStore } from "./person_dose_occurrences.ts";
import { createPersonInvitationAcceptanceStore } from "./person_invitation_acceptance.ts";
import { createPersonMedicationStore } from "./person_medications.ts";
import { createPersonTreatmentPlanStore } from "./person_treatment_plans.ts";
import { createPhoneCareInvitationStore } from "./phone_care_invitation.ts";
import { createProfileStore } from "./profile.ts";
import { createRawContactRetirementBootstrapStore } from "./raw_contact_retirement_bootstrap.ts";
import { ApiError } from "./validation.ts";

/** Compatibility facade around the existing application-data store. */
export function createLifeMateDatabase(
  databaseUrl: string,
  contactHashingSecret: string,
) {
  const database = createLegacyLifeMateDatabase(
    databaseUrl,
    contactHashingSecret,
  );
  const identityResolver = createIdentityResolver(databaseUrl);
  const invitationRevocation = createInvitationRevocationStore(databaseUrl);
  const personCareRelationships = createPersonCareRelationshipManagementStore(
    databaseUrl,
  );
  const personDoseOccurrences = createPersonDoseOccurrenceStore(databaseUrl);
  const personInvitationAcceptance = createPersonInvitationAcceptanceStore(
    databaseUrl,
    contactHashingSecret,
  );
  const personMedications = createPersonMedicationStore(databaseUrl);
  const personTreatmentPlans = createPersonTreatmentPlanStore(databaseUrl);
  const phoneInvitations = createPhoneCareInvitationStore(
    databaseUrl,
    contactHashingSecret,
  );
  const profiles = createProfileStore(databaseUrl, contactHashingSecret);
  const rawContactRetirement = rawContactRetirementEnabled();
  const retirementBootstrap = rawContactRetirement
    ? createRawContactRetirementBootstrapStore(
      databaseUrl,
      contactHashingSecret,
    )
    : null;

  async function currentUser(
    identity: Parameters<typeof database.currentUser>[0],
  ): Promise<Record<string, unknown>> {
    const current = await database.currentUser(identity);
    const legacyUser = current.user && typeof current.user === "object"
      ? current.user as Record<string, unknown>
      : {};
    return {
      ...current,
      user: {
        ...legacyUser,
        authSubject: identity.auth.id,
      },
      profile: await profiles.getProfile(identity.appUserId),
    };
  }

  async function bootstrapUser(
    auth: Parameters<typeof database.bootstrapUser>[0],
    body: Parameters<typeof database.bootstrapUser>[1],
  ): Promise<Record<string, unknown>> {
    if (identityResolver.lookupMode === "token-only") {
      try {
        const identity = await identityResolver.requireIdentity(auth);
        return await currentUser(identity);
      } catch (error) {
        if (
          !(error instanceof ApiError) ||
          error.status !== 404 ||
          error.code !== "not_onboarded"
        ) {
          throw error;
        }
      }
    }
    if (rawContactRetirement) {
      if (!retirementBootstrap) {
        throw new Error("raw_contact_retirement_bootstrap_unavailable");
      }
      const appUserId = await retirementBootstrap.bootstrapUser(auth, body);
      return await currentUser({ auth, appUserId });
    }
    return await database.bootstrapUser(auth, body);
  }

  return {
    ...database,
    bootstrapUser,
    requireIdentity: identityResolver.requireIdentity,
    identityLookupMode: identityResolver.lookupMode,
    currentUser,
    createMedication: personMedications.createMedication,
    listMedications: personMedications.listMedications,
    createTreatmentPlan: personTreatmentPlans.createTreatmentPlan,
    listTreatmentPlans: personTreatmentPlans.listTreatmentPlans,
    listDoseOccurrences: personDoseOccurrences.listDoseOccurrences,
    reportDose: personDoseOccurrences.reportDose,
    listCareDoseOccurrences: personDoseOccurrences.listCareDoseOccurrences,
    createInvitation: async (
      identity: Parameters<typeof database.createInvitation>[0],
      body: Parameters<typeof database.createInvitation>[1],
    ) => {
      const contactType = typeof body.contactType === "string"
        ? body.contactType.trim().toLowerCase()
        : "";
      if (contactType !== "phone") {
        return await database.createInvitation(identity, body);
      }

      throw new ApiError(
        410,
        "phone_care_invitation_retired",
        "Phone care invitations are retired. Use the care request flow.",
      );
    },
    createPhoneInvitation: phoneInvitations.createPhoneInvitation,
    revokeInvitation: invitationRevocation.revokePendingInvitation,
    acceptInvitation: (
      identity: Parameters<typeof database.acceptInvitation>[0],
      body: Parameters<typeof database.acceptInvitation>[1],
    ) =>
      phoneInvitations.acceptInvitationOrDelegate(
        identity,
        body,
        (_phoneIdentity, nonPhoneBody) =>
          personInvitationAcceptance.acceptInvitation(identity, nonPhoneBody),
      ),
    listRelationships: personCareRelationships.listRelationships,
    getNotificationPreferences:
      personCareRelationships.getNotificationPreferences,
    updateNotificationPreferences:
      personCareRelationships.updateNotificationPreferences,
    updateRelationshipPermissions: async (
      actorAppUserId: string,
      relationshipId: unknown,
      body: Record<string, unknown>,
    ) => {
      const nested = body.notificationPreferences;
      if (
        nested != null && typeof nested === "object" && !Array.isArray(nested)
      ) {
        return await personCareRelationships.updateNotificationPreferences(
          actorAppUserId,
          relationshipId,
          nested as Record<string, unknown>,
        );
      }
      return await personCareRelationships.updateRelationshipPermissions(
        actorAppUserId,
        relationshipId,
        body,
      );
    },
    revokeRelationship: personCareRelationships.revokeRelationship,
  };
}

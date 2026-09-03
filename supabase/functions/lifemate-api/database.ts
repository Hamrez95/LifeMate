export * from "./database_legacy.ts";

import { createBootstrapAccountStateGuard } from "./bootstrap_account_state.ts";
import { createCareCompletionNotificationStore } from "./care_completion_notifications.ts";
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
import {
  createPrivacyPreferenceStore,
  parseLegalAcceptances,
} from "./privacy_preferences.ts";
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
  const bootstrapAccountState = createBootstrapAccountStateGuard(databaseUrl);
  const identityResolver = createIdentityResolver(databaseUrl);
  const invitationRevocation = createInvitationRevocationStore(databaseUrl);
  const personCareRelationships = createPersonCareRelationshipManagementStore(
    databaseUrl,
  );
  const careCompletionNotifications = createCareCompletionNotificationStore(
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
  const privacyPreferences = createPrivacyPreferenceStore(databaseUrl);
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

  function bootstrappedAppUserId(
    value: Record<string, unknown>,
  ): string | null {
    if (typeof value.id === "string") return value.id;
    if (value.user && typeof value.user === "object") {
      const id = (value.user as Record<string, unknown>).id;
      if (typeof id === "string") return id;
    }
    return null;
  }

  async function bootstrapUser(
    auth: Parameters<typeof database.bootstrapUser>[0],
    body: Parameters<typeof database.bootstrapUser>[1],
  ): Promise<Record<string, unknown>> {
    if (body.registrationPreflight === true) {
      return {
        registration: {
          completed: false,
          requiredDocuments: await privacyPreferences.legalRequirements(),
        },
      };
    }

    const acceptances = parseLegalAcceptances(body.legalAcceptances);
    await privacyPreferences.assertAcceptancesCurrent(acceptances);
    await bootstrapAccountState.assertAllowed(auth.id);

    const bootstrapBody = { ...body };
    delete bootstrapBody.legalAcceptances;
    delete bootstrapBody.registrationPreflight;

    if (identityResolver.lookupMode === "token-only") {
      try {
        const identity = await identityResolver.requireIdentity(auth);
        const registration = await privacyPreferences.finalizeRegistration(
          identity.appUserId,
          acceptances,
        );
        return { ...(await currentUser(identity)), registration };
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

    let bootstrapped: Record<string, unknown>;
    if (rawContactRetirement) {
      if (!retirementBootstrap) {
        throw new Error("raw_contact_retirement_bootstrap_unavailable");
      }
      const appUserId = await retirementBootstrap.bootstrapUser(
        auth,
        bootstrapBody,
      );
      bootstrapped = await currentUser({ auth, appUserId });
    } else {
      bootstrapped = await database.bootstrapUser(auth, bootstrapBody);
    }

    const appUserId = bootstrappedAppUserId(bootstrapped);
    if (!appUserId) {
      throw new ApiError(
        503,
        "registration_identity_unavailable",
        "Registration identity is unavailable.",
      );
    }
    const registration = await privacyPreferences.finalizeRegistration(
      appUserId,
      acceptances,
    );
    return { ...bootstrapped, registration };
  }

  async function requireIdentity(
    auth: Parameters<typeof identityResolver.requireIdentity>[0],
  ) {
    const identity = await identityResolver.requireIdentity(auth);
    await privacyPreferences.requireRegistrationComplete(identity.appUserId);
    return identity;
  }

  async function listRelationships(
    appUserId: string,
  ): Promise<Record<string, unknown>[]> {
    const relationships = await personCareRelationships.listRelationships(
      appUserId,
    );
    for (const relationship of relationships) {
      relationship.recentCompletionNotifications = [];
      if (
        relationship.notificationPreferences == null ||
        typeof relationship.id !== "string"
      ) {
        continue;
      }
      relationship.recentCompletionNotifications =
        await careCompletionNotifications.history(appUserId, relationship.id);
    }
    return relationships;
  }

  return {
    ...database,
    bootstrapUser,
    requireIdentity,
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
      if (contactType === "phone") {
        return await phoneInvitations.createPhoneInvitation(identity, body);
      }
      return await database.createInvitation(identity, body);
    },
    createPhoneInvitation: phoneInvitations.createPhoneInvitation,
    previewInvitation: phoneInvitations.previewInvitation,
    revokeInvitation: invitationRevocation.revokePendingInvitation,
    acceptInvitation: async (
      identity: Parameters<typeof database.acceptInvitation>[0],
      body: Parameters<typeof database.acceptInvitation>[1],
    ) => {
      if (body.previewOnly === true) {
        return await phoneInvitations.previewInvitation(identity, body);
      }
      return await phoneInvitations.acceptInvitationOrDelegate(
        identity,
        body,
        (_phoneIdentity, nonPhoneBody) =>
          personInvitationAcceptance.acceptInvitation(identity, nonPhoneBody),
      );
    },
    listRelationships,
    getNotificationPreferences:
      personCareRelationships.getNotificationPreferences,
    updateNotificationPreferences:
      personCareRelationships.updateNotificationPreferences,
    updateRelationshipPresentation:
      personCareRelationships.updateRelationshipPresentation,
    updateRelationshipPermissions: async (
      actorAppUserId: string,
      relationshipId: unknown,
      body: Record<string, unknown>,
    ) => {
      if (body.claimCompletionNotifications === true) {
        return {
          completionNotifications: await careCompletionNotifications.claim(
            actorAppUserId,
            relationshipId,
          ),
        };
      }
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

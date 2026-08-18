export * from "./database_legacy.ts";

import {
  createLifeMateDatabase as createLegacyLifeMateDatabase,
} from "./database_legacy.ts";
import { createIdentityResolver } from "./identity_resolver.ts";
import { createInvitationRevocationStore } from "./invitation_revoke.ts";
import { createPersonDoseOccurrenceStore } from "./person_dose_occurrences.ts";
import { createPersonInvitationAcceptanceStore } from "./person_invitation_acceptance.ts";
import { createPersonMedicationStore } from "./person_medications.ts";
import { createPersonTreatmentPlanStore } from "./person_treatment_plans.ts";
import { createPhoneCareInvitationStore } from "./phone_care_invitation.ts";
import {
  createPhoneInvitationDeliveryFromEnvironment,
  type PhoneInvitationDelivery,
} from "./phone_invitation_delivery.ts";

export type LifeMateDatabaseOptions = {
  phoneInvitationDelivery?: PhoneInvitationDelivery;
};

/**
 * Compatibility facade around the existing application-data store.
 *
 * During the identity-link migration, all runtime callers keep the same
 * database API while authenticated-subject resolution is independently
 * switched from the legacy raw AppUser subject to the external-key token
 * boundary. The legacy implementation remains preserved in
 * database_legacy.ts so identity and invitation migrations stay reviewable and
 * reversible.
 */
export function createLifeMateDatabase(
  databaseUrl: string,
  contactHashingSecret: string,
  options: LifeMateDatabaseOptions = {},
) {
  const database = createLegacyLifeMateDatabase(
    databaseUrl,
    contactHashingSecret,
  );
  const identityResolver = createIdentityResolver(databaseUrl);
  const invitationRevocation = createInvitationRevocationStore(databaseUrl);
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

  return {
    ...database,
    requireIdentity: identityResolver.requireIdentity,
    identityLookupMode: identityResolver.lookupMode,
    // Medication ownership is canonical Person-based and new runtime writes no
    // longer create the legacy owner_user_id linkage. Existing legacy rows and
    // compatibility schema remain intact until destructive retirement is safe.
    createMedication: personMedications.createMedication,
    listMedications: personMedications.listMedications,
    // Treatment Plan ownership is canonical Person-based and new writes leave
    // the legacy patient_user_id compatibility column unset.
    createTreatmentPlan: personTreatmentPlans.createTreatmentPlan,
    listTreatmentPlans: personTreatmentPlans.listTreatmentPlans,
    // Dose materialization/read/report and caregiver authorization are
    // canonical Person-based; actor AppUser IDs remain audit provenance only.
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

      // Resolve provider configuration only for the phone path. Existing DB
      // callers and tests must not gain a new environment-permission dependency.
      const phoneInvitationDelivery = options.phoneInvitationDelivery ??
        createPhoneInvitationDeliveryFromEnvironment();
      phoneInvitationDelivery.requireEnabled();
      const created = await phoneInvitations.createPhoneInvitation(
        identity,
        body,
        ({ phoneE164, token }) =>
          phoneInvitationDelivery.deliver(phoneE164, token),
      );

      // The raw one-time token never crosses the public API boundary. It exists
      // only long enough to be delivered to Kavenegar inside the transaction.
      return {
        id: created.id,
        contactType: created.contactType,
        contactHint: created.contactHint,
        expiresAtUtc: created.expiresAtUtc,
      };
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
  };
}

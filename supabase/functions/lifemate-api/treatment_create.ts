import { getLifeMateSql } from "./database_client.ts";
import { createPersonMedicationStore } from "./person_medications.ts";
import { createPersonTreatmentPlanStore } from "./person_treatment_plans.ts";
import { ApiError } from "./validation.ts";

function requiredObject(
  value: unknown,
  field: string,
): Record<string, unknown> {
  if (value == null || typeof value !== "object" || Array.isArray(value)) {
    throw new ApiError(400, `invalid_${field}`, `${field} is required.`);
  }
  return value as Record<string, unknown>;
}

/**
 * Creates the medication and its first treatment plan as one PostgreSQL
 * transaction. A failure in plan validation/schedule persistence therefore
 * rolls back the medication and its audit row as well.
 *
 * Request-level retry identity remains owned by the shared API idempotency
 * coordinator, so duplicate network submissions with the same Idempotency-Key
 * converge on this single logical transaction.
 */
export function createAtomicTreatmentStore(databaseUrl: string) {
  const sql = getLifeMateSql(databaseUrl);
  const medications = createPersonMedicationStore(databaseUrl);
  const treatmentPlans = createPersonTreatmentPlanStore(databaseUrl);

  async function createTreatment(
    appUserId: string,
    body: Record<string, unknown>,
  ): Promise<Record<string, unknown>> {
    const medicationInput = requiredObject(body.medication, "medication");
    const treatmentInput = requiredObject(body.treatmentPlan, "treatmentPlan");

    return await sql.begin(async (tx: any) => {
      const medication = await medications.createMedicationInTransaction(
        tx,
        appUserId,
        medicationInput,
      );
      const medicationId = String(medication.id ?? "");
      if (medicationId.length === 0) {
        throw new Error("atomic_treatment_medication_id_missing");
      }
      const treatmentPlan = await treatmentPlans.createTreatmentPlanInTransaction(
        tx,
        appUserId,
        {
          ...treatmentInput,
          medicationId,
        },
      );
      return {
        contractVersion: 1,
        medication,
        treatmentPlan,
      };
    });
  }

  return { createTreatment };
}

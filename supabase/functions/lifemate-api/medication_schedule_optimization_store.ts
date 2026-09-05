import { getLifeMateSql } from "./database_client.ts";
import {
  buildNearbyDoseProposal,
  medicationScheduleOptimizationAlgorithmVersion,
  type NearbyDosePlanCandidate,
} from "./medication_schedule_optimization.ts";
import { ApiError, requiredUuid } from "./validation.ts";

type Row = Record<string, any>;

const proposalLifetimeMinutes = 15;

async function requireSelfPerson(
  connection: any,
  appUserId: string,
): Promise<string> {
  const rows = await connection`
    select core.self_person_id_for_legacy_app_user(${appUserId}::uuid)::text as person_id
  `;
  const personId = rows[0]?.person_id;
  if (typeof personId !== "string" || personId.length === 0) {
    throw new ApiError(
      409,
      "identity_person_mapping_missing",
      "Person mapping is unavailable.",
    );
  }
  return personId;
}

function recurrenceIntervalHours(row: Row): number | null {
  const raw = row.recurrence_rule;
  const recurrence = typeof raw === "string" ? JSON.parse(raw) : raw;
  if (
    !recurrence || recurrence.enabled !== true || recurrence.unit !== "hour"
  ) {
    return null;
  }
  const interval = Number(recurrence.interval);
  return Number.isInteger(interval) && interval >= 1 && interval <= 8760
    ? interval
    : null;
}

function time(value: unknown): string {
  return String(value).slice(0, 5);
}

export function createMedicationScheduleOptimizationStore(databaseUrl: string) {
  const sql = getLifeMateSql(databaseUrl);

  async function preview(appUserId: string): Promise<Record<string, unknown>> {
    return await sql.begin(async (tx: any) => {
      const ownerPersonId = await requireSelfPerson(tx, appUserId);
      const rows = await tx`
        select p.id, p.version as treatment_plan_version,
               p.recurrence_rule, p.recurrence_start_local_time::text,
               m.name as medication_name,
               c.nearby_grouping_enabled, c.timing_locked,
               c.manual_spacing_before_minutes,c.manual_spacing_after_minutes,
               c.version as timing_version
        from lifemate.treatment_plans p
        join lifemate.medications m
          on m.id=p.medication_id and m.owner_person_id=p.patient_person_id
        left join lifemate.treatment_plan_timing_constraints c
          on c.treatment_plan_id=p.id and c.owner_person_id=p.patient_person_id
        where p.patient_person_id=${ownerPersonId}::uuid
          and p.status='Active'
          and p.recurrence_rule is not null
          and p.recurrence_start_local_time is not null
        order by p.id
        limit 100
      `;

      const candidates: NearbyDosePlanCandidate[] = [];
      for (const row of rows) {
        const intervalHours = recurrenceIntervalHours(row);
        if (intervalHours == null) continue;
        candidates.push({
          treatmentPlanId: String(row.id),
          medicationName: String(row.medication_name),
          anchorLocalTime: time(row.recurrence_start_local_time),
          intervalHours,
          treatmentPlanVersion: Number(row.treatment_plan_version),
          timingVersion: Number(row.timing_version ?? 0),
          nearbyGroupingEnabled: row.nearby_grouping_enabled === true,
          timingLocked: row.timing_locked === true,
          manualSpacingBeforeMinutes: Number(
            row.manual_spacing_before_minutes ?? 0,
          ),
          manualSpacingAfterMinutes: Number(
            row.manual_spacing_after_minutes ?? 0,
          ),
        });
      }

      const proposal = buildNearbyDoseProposal(candidates);
      const proposalId = crypto.randomUUID();
      const expires = new Date(Date.now() + proposalLifetimeMinutes * 60_000);
      await tx`
        insert into lifemate.medication_schedule_optimization_proposals
          (id,owner_person_id,algorithm_version,status,
           expected_notification_reduction,expires_at_utc,
           created_at_utc,updated_at_utc)
        values
          (${proposalId}::uuid,${ownerPersonId}::uuid,
           ${medicationScheduleOptimizationAlgorithmVersion},'Previewed',
           ${proposal.expectedNotificationReduction},${expires},now(),now())
      `;
      for (const group of proposal.groups) {
        for (const change of group.changes) {
          await tx`
            insert into lifemate.medication_schedule_optimization_plan_changes
              (proposal_id,treatment_plan_id,owner_person_id,
               old_anchor_local_time,new_anchor_local_time,interval_hours,
               expected_treatment_plan_version,expected_timing_version,
               shift_minutes,created_at_utc)
            values
              (${proposalId}::uuid,${change.treatmentPlanId}::uuid,
               ${ownerPersonId}::uuid,${change.oldAnchorLocalTime}::time,
               ${change.newAnchorLocalTime}::time,${change.intervalHoursBefore},
               ${change.treatmentPlanVersion},${change.timingVersion},
               ${change.shiftMinutes},now())
          `;
        }
      }
      return {
        proposalId,
        expiresAtUtc: expires.toISOString(),
        ...proposal,
      };
    });
  }

  async function apply(
    appUserId: string,
    proposalIdValue: unknown,
  ): Promise<Record<string, unknown>> {
    const proposalId = requiredUuid(proposalIdValue, "proposalId");
    return await sql.begin(async (tx: any) => {
      const ownerPersonId = await requireSelfPerson(tx, appUserId);
      const proposalRows = await tx`
        select * from lifemate.medication_schedule_optimization_proposals
        where id=${proposalId}::uuid and owner_person_id=${ownerPersonId}::uuid
        for update
      `;
      const proposal = proposalRows[0];
      if (!proposal) {
        throw new ApiError(
          404,
          "optimization_proposal_missing",
          "Proposal was not found.",
        );
      }
      if (proposal.status === "Applied") {
        return { proposalId, status: "applied", alreadyApplied: true };
      }
      if (proposal.status !== "Previewed") {
        throw new ApiError(
          409,
          "optimization_proposal_inactive",
          "Proposal is no longer active.",
        );
      }
      if (new Date(proposal.expires_at_utc).getTime() <= Date.now()) {
        await tx`
          update lifemate.medication_schedule_optimization_proposals
          set status='Expired',updated_at_utc=now()
          where id=${proposalId}::uuid
        `;
        throw new ApiError(
          409,
          "optimization_proposal_expired",
          "Proposal expired. Preview again.",
        );
      }

      const changes = await tx`
        select * from lifemate.medication_schedule_optimization_plan_changes
        where proposal_id=${proposalId}::uuid
          and owner_person_id=${ownerPersonId}::uuid
        order by treatment_plan_id
        for update
      `;
      if (changes.length === 0) {
        throw new ApiError(
          409,
          "optimization_no_changes",
          "Proposal has no applicable changes.",
        );
      }

      for (const change of changes) {
        const planRows = await tx`
          select p.version,p.recurrence_rule,p.recurrence_start_local_time::text,
                 c.version as timing_version,c.nearby_grouping_enabled,
                 c.timing_locked,c.manual_spacing_before_minutes,
                 c.manual_spacing_after_minutes
          from lifemate.treatment_plans p
          left join lifemate.treatment_plan_timing_constraints c
            on c.treatment_plan_id=p.id and c.owner_person_id=p.patient_person_id
          where p.id=${change.treatment_plan_id}::uuid
            and p.patient_person_id=${ownerPersonId}::uuid
            and p.status='Active'
          for update of p
        `;
        const plan = planRows[0];
        if (!plan) {
          throw new ApiError(
            409,
            "stale_treatment_plan",
            "Treatment plan changed. Preview again.",
          );
        }
        const intervalHours = recurrenceIntervalHours(plan);
        if (
          Number(plan.version) !==
            Number(change.expected_treatment_plan_version) ||
          Number(plan.timing_version ?? 0) !==
            Number(change.expected_timing_version) ||
          intervalHours !== Number(change.interval_hours) ||
          time(plan.recurrence_start_local_time) !==
            time(change.old_anchor_local_time) ||
          plan.nearby_grouping_enabled !== true ||
          plan.timing_locked === true ||
          Number(plan.manual_spacing_before_minutes ?? 0) > 0 ||
          Number(plan.manual_spacing_after_minutes ?? 0) > 0
        ) {
          throw new ApiError(
            409,
            "stale_schedule_proposal",
            "Schedule changed. Preview again.",
          );
        }
      }

      const applied: Record<string, unknown>[] = [];
      for (const change of changes) {
        const updated = await tx`
          update lifemate.treatment_plans
          set recurrence_start_local_time=${
          time(change.new_anchor_local_time)
        }::time,
              version=version+1,updated_at_utc=now()
          where id=${change.treatment_plan_id}::uuid
            and patient_person_id=${ownerPersonId}::uuid
          returning id,version,recurrence_start_local_time::text
        `;
        await tx`
          update lifemate.medication_schedule_optimization_plan_changes
          set applied_treatment_plan_version=${Number(updated[0].version)}
          where proposal_id=${proposalId}::uuid
            and treatment_plan_id=${change.treatment_plan_id}::uuid
            and owner_person_id=${ownerPersonId}::uuid
        `;
        await tx`
          update lifemate.treatment_schedules
          set local_time=${time(change.new_anchor_local_time)}::time
          where treatment_plan_id=${change.treatment_plan_id}::uuid
            and lower(day_of_week)='recurrence'
        `;
        // Historical truth is immutable. Only future not-yet-acted-on Scheduled
        // materialization is removed; it is recreated from the new exact anchor
        // by the canonical occurrence materializer on the next bounded read.
        await tx`
          delete from lifemate.dose_occurrences
          where treatment_plan_id=${change.treatment_plan_id}::uuid
            and patient_person_id=${ownerPersonId}::uuid
            and status='Scheduled'
            and scheduled_at_utc > now()
        `;
        applied.push({
          treatmentPlanId: updated[0].id,
          version: Number(updated[0].version),
          newAnchorLocalTime: time(updated[0].recurrence_start_local_time),
          intervalHours: Number(change.interval_hours),
        });
      }

      await tx`
        update lifemate.medication_schedule_optimization_proposals
        set status='Applied',confirmed_at_utc=now(),applied_at_utc=now(),
            updated_at_utc=now()
        where id=${proposalId}::uuid
      `;
      return {
        proposalId,
        status: "applied",
        algorithmVersion: proposal.algorithm_version,
        expectedNotificationReduction: Number(
          proposal.expected_notification_reduction,
        ),
        applied,
      };
    });
  }

  async function undo(
    appUserId: string,
    proposalIdValue: unknown,
  ): Promise<Record<string, unknown>> {
    const proposalId = requiredUuid(proposalIdValue, "proposalId");
    return await sql.begin(async (tx: any) => {
      const ownerPersonId = await requireSelfPerson(tx, appUserId);
      const proposalRows = await tx`
        select * from lifemate.medication_schedule_optimization_proposals
        where id=${proposalId}::uuid and owner_person_id=${ownerPersonId}::uuid
        for update
      `;
      const proposal = proposalRows[0];
      if (!proposal) {
        throw new ApiError(
          404,
          "optimization_proposal_missing",
          "Proposal was not found.",
        );
      }
      if (proposal.status === "Undone") {
        return { proposalId, status: "undone", alreadyUndone: true };
      }
      if (proposal.status !== "Applied") {
        throw new ApiError(
          409,
          "optimization_undo_unavailable",
          "Only an applied proposal can be undone.",
        );
      }

      const changes = await tx`
        select * from lifemate.medication_schedule_optimization_plan_changes
        where proposal_id=${proposalId}::uuid
          and owner_person_id=${ownerPersonId}::uuid
        order by treatment_plan_id
        for update
      `;
      if (changes.length === 0) {
        throw new ApiError(
          409,
          "optimization_no_changes",
          "Proposal has no applicable changes.",
        );
      }

      for (const change of changes) {
        const planRows = await tx`
          select p.version,p.recurrence_rule,p.recurrence_start_local_time::text,
                 p.status,c.version as timing_version
          from lifemate.treatment_plans p
          left join lifemate.treatment_plan_timing_constraints c
            on c.treatment_plan_id=p.id and c.owner_person_id=p.patient_person_id
          where p.id=${change.treatment_plan_id}::uuid
            and p.patient_person_id=${ownerPersonId}::uuid
          for update of p
        `;
        const plan = planRows[0];
        if (
          !plan ||
          plan.status !== "Active" ||
          change.applied_treatment_plan_version == null ||
          Number(plan.version) !==
            Number(change.applied_treatment_plan_version) ||
          Number(plan.timing_version ?? 0) !==
            Number(change.expected_timing_version) ||
          recurrenceIntervalHours(plan) !== Number(change.interval_hours) ||
          time(plan.recurrence_start_local_time) !==
            time(change.new_anchor_local_time)
        ) {
          throw new ApiError(
            409,
            "optimization_undo_stale",
            "The schedule changed after apply. Undo requires a fresh review.",
          );
        }
      }

      const undone: Record<string, unknown>[] = [];
      for (const change of changes) {
        const updated = await tx`
          update lifemate.treatment_plans
          set recurrence_start_local_time=${
          time(change.old_anchor_local_time)
        }::time,
              version=version+1,updated_at_utc=now()
          where id=${change.treatment_plan_id}::uuid
            and patient_person_id=${ownerPersonId}::uuid
          returning id,version,recurrence_start_local_time::text
        `;
        await tx`
          update lifemate.treatment_schedules
          set local_time=${time(change.old_anchor_local_time)}::time
          where treatment_plan_id=${change.treatment_plan_id}::uuid
            and lower(day_of_week)='recurrence'
        `;
        await tx`
          delete from lifemate.dose_occurrences
          where treatment_plan_id=${change.treatment_plan_id}::uuid
            and patient_person_id=${ownerPersonId}::uuid
            and status='Scheduled'
            and scheduled_at_utc > now()
        `;
        undone.push({
          treatmentPlanId: updated[0].id,
          version: Number(updated[0].version),
          restoredAnchorLocalTime: time(updated[0].recurrence_start_local_time),
          intervalHours: Number(change.interval_hours),
        });
      }

      await tx`
        update lifemate.medication_schedule_optimization_proposals
        set status='Undone',undone_at_utc=now(),updated_at_utc=now()
        where id=${proposalId}::uuid and owner_person_id=${ownerPersonId}::uuid
      `;
      return {
        proposalId,
        status: "undone",
        undone,
      };
    });
  }

  return { preview, apply, undo };
}

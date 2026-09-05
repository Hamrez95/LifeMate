import { getLifeMateSql } from "./database_client.ts";
import {
  medicationSleepSolverAlgorithmVersion,
  proposeExactSleepAwareAnchor,
  proposeFlexibleSleepAwareSequence,
} from "./medication_schedule_sleep_solver.ts";
import {
  ApiError,
  requiredDate,
  requiredPositiveInt,
  requiredUuid,
} from "./validation.ts";

type Row = Record<string, any>;

type SleepOptimizationMode = "strict_anchor_shift" | "flexible_interval";

const consentTextVersion = "sleep-flex-consent-v1";
const previewLifetimeMinutes = 15;
const maxEffectiveDays = 14;

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

function requiredMode(value: unknown): SleepOptimizationMode {
  if (value === "strict_anchor_shift" || value === "flexible_interval") {
    return value;
  }
  throw new ApiError(
    400,
    "invalid_optimization_mode",
    "A supported mode is required.",
  );
}

function requiredVariation(value: unknown): number {
  const parsed = Number(value);
  if (
    !Number.isInteger(parsed) || parsed < 5 || parsed > 180 || parsed % 5 !== 0
  ) {
    throw new ApiError(
      400,
      "invalid_variation_bound",
      "maxVariationMinutes must be a 5-minute step from 5 to 180.",
    );
  }
  return parsed;
}

function dateUtc(value: string): Date {
  return new Date(`${value}T00:00:00Z`);
}

function dateSpanDays(from: string, until: string): number {
  return Math.floor(
    (dateUtc(until).getTime() - dateUtc(from).getTime()) / 86_400_000,
  ) + 1;
}

function recurrenceIntervalHours(row: Row): number | null {
  const raw = row.recurrence_rule;
  const recurrence = typeof raw === "string" ? JSON.parse(raw) : raw;
  if (
    !recurrence || recurrence.enabled !== true || recurrence.unit !== "hour"
  ) return null;
  const interval = Number(recurrence.interval);
  return Number.isInteger(interval) && interval >= 1 && interval <= 8760
    ? interval
    : null;
}

function localTime(value: unknown): string {
  return String(value).slice(0, 5);
}

function localPoint(baseDate: string, anchor: string, minuteOffset: number): {
  date: string;
  time: string;
} {
  const [hour, minute] = anchor.split(":").map(Number);
  const value = dateUtc(baseDate);
  value.setUTCMinutes(hour * 60 + minute + minuteOffset);
  return {
    date: value.toISOString().slice(0, 10),
    time: value.toISOString().slice(11, 16),
  };
}

async function sha256Hex(value: string): Promise<string> {
  const bytes = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

export function createMedicationScheduleSleepStore(databaseUrl: string) {
  const sql = getLifeMateSql(databaseUrl);

  async function preview(
    appUserId: string,
    body: Record<string, unknown>,
  ): Promise<Record<string, unknown>> {
    const mode = requiredMode(body.mode);
    const effectiveFrom = requiredDate(
      body.effectiveFromLocalDate,
      "effectiveFromLocalDate",
    );
    const effectiveUntil = requiredDate(
      body.effectiveUntilLocalDate,
      "effectiveUntilLocalDate",
    );
    const spanDays = dateSpanDays(effectiveFrom, effectiveUntil);
    if (spanDays < 1 || spanDays > maxEffectiveDays) {
      throw new ApiError(
        400,
        "invalid_effective_range",
        `The approved range must be between 1 and ${maxEffectiveDays} days.`,
      );
    }
    const maxVariation = mode === "flexible_interval"
      ? requiredVariation(body.maxVariationMinutes)
      : null;

    return await sql.begin(async (tx: any) => {
      const ownerPersonId = await requireSelfPerson(tx, appUserId);
      const preferenceRows = await tx`
        select time_zone,sleep_window_enabled,sleep_start_local_time::text,
               sleep_end_local_time::text,version
        from lifemate.medication_schedule_preferences
        where owner_person_id=${ownerPersonId}::uuid
        limit 1
      `;
      const preferences = preferenceRows[0];
      if (
        !preferences ||
        preferences.sleep_window_enabled !== true ||
        preferences.sleep_start_local_time == null ||
        preferences.sleep_end_local_time == null
      ) {
        throw new ApiError(
          409,
          "sleep_preferences_required",
          "Enable sleep preferences before preparing this proposal.",
        );
      }

      const sleep = {
        startLocalTime: localTime(preferences.sleep_start_local_time),
        endLocalTime: localTime(preferences.sleep_end_local_time),
      };
      const sleepSnapshotHash = await sha256Hex(
        `${preferences.version}|${preferences.time_zone}|${sleep.startLocalTime}|${sleep.endLocalTime}`,
      );
      const planRows = await tx`
        select p.id,p.version,p.time_zone,p.start_date,p.end_date,
               p.recurrence_rule,p.recurrence_start_local_time::text,
               m.name as medication_name,
               c.version as timing_version,c.timing_locked,
               c.manual_spacing_before_minutes,c.manual_spacing_after_minutes
        from lifemate.treatment_plans p
        join lifemate.medications m
          on m.id=p.medication_id and m.owner_person_id=p.patient_person_id
        left join lifemate.treatment_plan_timing_constraints c
          on c.treatment_plan_id=p.id and c.owner_person_id=p.patient_person_id
        where p.patient_person_id=${ownerPersonId}::uuid
          and p.status='Active'
          and p.recurrence_rule is not null
          and p.recurrence_start_local_time is not null
          and p.start_date <= ${effectiveUntil}::date
          and (p.end_date is null or p.end_date >= ${effectiveFrom}::date)
        order by p.id
        limit 100
      `;

      const runId = crypto.randomUUID();
      const expires = new Date(Date.now() + previewLifetimeMinutes * 60_000);
      await tx`
        insert into lifemate.medication_schedule_optimization_runs
          (id,owner_person_id,mode,algorithm_version,consent_text_version,
           schedule_preferences_version,sleep_window_enabled,
           sleep_window_snapshot_hash,max_variation_minutes,
           effective_from_local_date,effective_until_local_date,status,
           expires_at_utc,created_at_utc,updated_at_utc)
        values
          (${runId}::uuid,${ownerPersonId}::uuid,${mode},
           ${medicationSleepSolverAlgorithmVersion},${consentTextVersion},
           ${
        Number(preferences.version)
      },true,${sleepSnapshotHash},${maxVariation},
           ${effectiveFrom}::date,${effectiveUntil}::date,'Previewed',${expires},now(),now())
      `;

      const proposals: Record<string, unknown>[] = [];
      const exclusions: Record<string, unknown>[] = [];
      for (const plan of planRows) {
        const intervalHours = recurrenceIntervalHours(plan);
        if (intervalHours == null) continue;
        const medicationName = String(plan.medication_name);
        if (plan.timing_locked === true) {
          exclusions.push({
            treatmentPlanId: plan.id,
            medicationName,
            reason: "timing_locked",
          });
          continue;
        }
        if (
          Number(plan.manual_spacing_before_minutes ?? 0) > 0 ||
          Number(plan.manual_spacing_after_minutes ?? 0) > 0
        ) {
          exclusions.push({
            treatmentPlanId: plan.id,
            medicationName,
            reason: "manual_spacing",
          });
          continue;
        }

        const changeId = crypto.randomUUID();
        const oldAnchor = localTime(plan.recurrence_start_local_time);
        if (mode === "strict_anchor_shift") {
          const horizonDoseCount = Math.min(
            64,
            Math.max(2, Math.ceil(spanDays * 24 / intervalHours) + 1),
          );
          const proposal = proposeExactSleepAwareAnchor({
            anchorLocalTime: oldAnchor,
            intervalHours,
            sleep,
            horizonDoseCount,
          });
          if (
            proposal.newAnchorLocalTime === proposal.oldAnchorLocalTime ||
            proposal.sleepHitsAfter >= proposal.sleepHitsBefore
          ) {
            exclusions.push({
              treatmentPlanId: plan.id,
              medicationName,
              reason: "no_better_exact_anchor",
            });
            continue;
          }
          await tx`
            insert into lifemate.medication_schedule_optimization_changes
              (id,run_id,owner_person_id,treatment_plan_id,
               expected_treatment_plan_version,expected_timing_version,
               entered_interval_minutes,old_anchor_local_time,
               proposed_anchor_local_time,reason,created_at_utc)
            values
              (${changeId}::uuid,${runId}::uuid,${ownerPersonId}::uuid,
               ${plan.id}::uuid,${Number(plan.version)},${
            Number(plan.timing_version ?? 0)
          },
               ${intervalHours * 60},${proposal.oldAnchorLocalTime}::time,
               ${proposal.newAnchorLocalTime}::time,'sleep_preference',now())
          `;
          proposals.push({
            treatmentPlanId: plan.id,
            medicationName,
            intervalHours,
            ...proposal,
          });
          continue;
        }

        const doseCount = Math.min(
          64,
          Math.max(2, Math.ceil(spanDays * 24 / intervalHours) + 1),
        );
        const sequence = proposeFlexibleSleepAwareSequence({
          anchorLocalTime: oldAnchor,
          intervalHours,
          maxVariationMinutes: maxVariation!,
          doseCount,
          sleep,
        });
        if (
          !sequence.feasible ||
          sequence.sleepHitsAfter >= sequence.sleepHitsBefore
        ) {
          exclusions.push({
            treatmentPlanId: plan.id,
            medicationName,
            reason: "no_better_flexible_sequence",
          });
          continue;
        }
        await tx`
          insert into lifemate.medication_schedule_optimization_changes
            (id,run_id,owner_person_id,treatment_plan_id,
             expected_treatment_plan_version,expected_timing_version,
             entered_interval_minutes,old_anchor_local_time,
             proposed_anchor_local_time,reason,created_at_utc)
          values
            (${changeId}::uuid,${runId}::uuid,${ownerPersonId}::uuid,
             ${plan.id}::uuid,${Number(plan.version)},${
          Number(plan.timing_version ?? 0)
        },
             ${
          intervalHours * 60
        },${oldAnchor}::time,null,'sleep_preference',now())
        `;

        const overridePreview: Record<string, unknown>[] = [];
        for (const occurrence of sequence.occurrences) {
          const original = localPoint(
            effectiveFrom,
            oldAnchor,
            occurrence.originalMinuteOffset,
          );
          const replacement = localPoint(
            effectiveFrom,
            oldAnchor,
            occurrence.proposedMinuteOffset,
          );
          if (original.date < effectiveFrom || original.date > effectiveUntil) {
            continue;
          }
          await tx`
            insert into lifemate.dose_occurrence_overrides
              (id,run_id,change_id,owner_person_id,treatment_plan_id,
               original_local_date,original_local_time,replacement_local_date,
               replacement_local_time,time_zone,entered_interval_minutes,
               actual_gap_minutes,variation_minutes,status,created_at_utc,updated_at_utc)
            values
              (${crypto.randomUUID()}::uuid,${runId}::uuid,${changeId}::uuid,
               ${ownerPersonId}::uuid,${plan.id}::uuid,${original.date}::date,
               ${original.time}::time,${replacement.date}::date,
               ${replacement.time}::time,${plan.time_zone},${
            intervalHours * 60
          },
               ${occurrence.proposedGapMinutes},${occurrence.variationMinutes},
               'Active',now(),now())
          `;
          overridePreview.push({
            originalLocalDate: original.date,
            originalLocalTime: original.time,
            proposedLocalDate: replacement.date,
            proposedLocalTime: replacement.time,
            enteredGapMinutes: occurrence.previousGapMinutes,
            proposedGapMinutes: occurrence.proposedGapMinutes,
            variationMinutes: occurrence.variationMinutes,
            sleepHitBefore: occurrence.sleepHitBefore,
            sleepHitAfter: occurrence.sleepHitAfter,
          });
        }
        proposals.push({
          treatmentPlanId: plan.id,
          medicationName,
          mode,
          intervalHours,
          maxVariationMinutes: maxVariation,
          sleepHitsBefore: sequence.sleepHitsBefore,
          sleepHitsAfter: sequence.sleepHitsAfter,
          occurrences: overridePreview,
        });
      }

      return {
        runId,
        proposalId: runId,
        mode,
        algorithmVersion: medicationSleepSolverAlgorithmVersion,
        consentTextVersion,
        effectiveFromLocalDate: effectiveFrom,
        effectiveUntilLocalDate: effectiveUntil,
        maxVariationMinutes: maxVariation,
        expiresAtUtc: expires.toISOString(),
        proposals,
        exclusions,
      };
    });
  }

  async function apply(
    appUserId: string,
    runIdValue: unknown,
    body: Record<string, unknown>,
  ): Promise<Record<string, unknown>> {
    const runId = requiredUuid(runIdValue, "proposalId");
    const selectedMode = requiredMode(body.mode);
    if (body.acknowledgedTimingChanges !== true) {
      throw new ApiError(
        400,
        "timing_acknowledgement_required",
        "Explicit acknowledgement of the displayed timing changes is required.",
      );
    }

    return await sql.begin(async (tx: any) => {
      const ownerPersonId = await requireSelfPerson(tx, appUserId);
      const runRows = await tx`
        select * from lifemate.medication_schedule_optimization_runs
        where id=${runId}::uuid and owner_person_id=${ownerPersonId}::uuid
        for update
      `;
      const run = runRows[0];
      if (!run) {
        throw new ApiError(
          404,
          "optimization_run_missing",
          "Proposal was not found.",
        );
      }
      if (run.status === "Applied") {
        return { runId, status: "applied", alreadyApplied: true };
      }
      if (run.status !== "Previewed" || run.mode !== selectedMode) {
        throw new ApiError(
          409,
          "stale_schedule_proposal",
          "Proposal is no longer valid.",
        );
      }
      if (new Date(run.expires_at_utc).getTime() <= Date.now()) {
        await tx`update lifemate.medication_schedule_optimization_runs set status='Expired',updated_at_utc=now() where id=${runId}::uuid`;
        throw new ApiError(
          409,
          "optimization_proposal_expired",
          "Proposal expired. Preview again.",
        );
      }

      const preferences = await tx`
        select time_zone,sleep_window_enabled,sleep_start_local_time::text,
               sleep_end_local_time::text,version
        from lifemate.medication_schedule_preferences
        where owner_person_id=${ownerPersonId}::uuid
        for update
      `;
      const currentPreferences = preferences[0];
      if (
        !currentPreferences ||
        currentPreferences.sleep_window_enabled !== true ||
        Number(currentPreferences.version) !==
          Number(run.schedule_preferences_version)
      ) {
        throw new ApiError(
          409,
          "stale_sleep_preferences",
          "Sleep preferences changed. Preview again.",
        );
      }
      const currentSleepHash = await sha256Hex(
        `${currentPreferences.version}|${currentPreferences.time_zone}|${
          localTime(currentPreferences.sleep_start_local_time)
        }|${localTime(currentPreferences.sleep_end_local_time)}`,
      );
      if (currentSleepHash !== run.sleep_window_snapshot_hash) {
        throw new ApiError(
          409,
          "stale_sleep_preferences",
          "Sleep preferences changed. Preview again.",
        );
      }

      const changes = await tx`
        select c.*,p.version as current_plan_version,p.recurrence_rule,
               p.recurrence_start_local_time::text,p.status,
               tc.version as current_timing_version,tc.timing_locked,
               tc.manual_spacing_before_minutes,tc.manual_spacing_after_minutes
        from lifemate.medication_schedule_optimization_changes c
        join lifemate.treatment_plans p on p.id=c.treatment_plan_id
        left join lifemate.treatment_plan_timing_constraints tc
          on tc.treatment_plan_id=p.id and tc.owner_person_id=p.patient_person_id
        where c.run_id=${runId}::uuid and c.owner_person_id=${ownerPersonId}::uuid
        order by c.treatment_plan_id
        for update of p
      `;
      if (changes.length === 0) {
        throw new ApiError(
          409,
          "optimization_no_changes",
          "Proposal has no applicable changes.",
        );
      }
      for (const change of changes) {
        const intervalHours = recurrenceIntervalHours(change);
        if (
          change.status !== undefined && change.status !== "Active" ||
          Number(change.current_plan_version) !==
            Number(change.expected_treatment_plan_version) ||
          Number(change.current_timing_version ?? 0) !==
            Number(change.expected_timing_version) ||
          intervalHours == null ||
          intervalHours * 60 !== Number(change.entered_interval_minutes) ||
          change.timing_locked === true ||
          Number(change.manual_spacing_before_minutes ?? 0) > 0 ||
          Number(change.manual_spacing_after_minutes ?? 0) > 0
        ) {
          throw new ApiError(
            409,
            "stale_schedule_proposal",
            "Schedule changed. Preview again.",
          );
        }
      }

      if (selectedMode === "strict_anchor_shift") {
        for (const change of changes) {
          await tx`
            update lifemate.treatment_plans
            set recurrence_start_local_time=${
            localTime(change.proposed_anchor_local_time)
          }::time,
                version=version+1,updated_at_utc=now()
            where id=${change.treatment_plan_id}::uuid
              and patient_person_id=${ownerPersonId}::uuid
          `;
          await tx`
            update lifemate.treatment_schedules
            set local_time=${localTime(change.proposed_anchor_local_time)}::time
            where treatment_plan_id=${change.treatment_plan_id}::uuid
              and lower(day_of_week)='recurrence'
          `;
          await tx`
            delete from lifemate.dose_occurrences
            where treatment_plan_id=${change.treatment_plan_id}::uuid
              and patient_person_id=${ownerPersonId}::uuid
              and status='Scheduled' and scheduled_at_utc > now()
          `;
        }
      } else {
        // Flexible mode intentionally leaves canonical recurrence untouched.
        // Overrides were fully materialized at preview and are activated only
        // by flipping the run to Applied after every version check succeeds.
        await tx`
          update lifemate.dose_occurrence_overrides
          set updated_at_utc=now()
          where run_id=${runId}::uuid and owner_person_id=${ownerPersonId}::uuid
            and status='Active'
        `;
      }

      await tx`
        update lifemate.medication_schedule_optimization_runs
        set status='Applied',confirmed_at_utc=now(),applied_at_utc=now(),updated_at_utc=now()
        where id=${runId}::uuid
      `;
      return {
        runId,
        status: "applied",
        mode: selectedMode,
        effectiveFromLocalDate: String(run.effective_from_local_date).slice(
          0,
          10,
        ),
        effectiveUntilLocalDate: String(run.effective_until_local_date).slice(
          0,
          10,
        ),
        consentTextVersion: run.consent_text_version,
      };
    });
  }

  async function undo(
    appUserId: string,
    runIdValue: unknown,
  ): Promise<Record<string, unknown>> {
    const runId = requiredUuid(runIdValue, "runId");
    return await sql.begin(async (tx: any) => {
      const ownerPersonId = await requireSelfPerson(tx, appUserId);
      const rows = await tx`
        select * from lifemate.medication_schedule_optimization_runs
        where id=${runId}::uuid and owner_person_id=${ownerPersonId}::uuid
        for update
      `;
      const run = rows[0];
      if (!run) {
        throw new ApiError(
          404,
          "optimization_run_missing",
          "Optimization was not found.",
        );
      }
      if (run.status === "Undone") {
        return { runId, status: "undone", alreadyUndone: true };
      }
      if (run.status !== "Applied") {
        throw new ApiError(
          409,
          "optimization_not_undoable",
          "Only an applied optimization can be undone.",
        );
      }

      const changes = await tx`
        select * from lifemate.medication_schedule_optimization_changes
        where run_id=${runId}::uuid and owner_person_id=${ownerPersonId}::uuid
        order by treatment_plan_id for update
      `;
      if (run.mode === "strict_anchor_shift") {
        for (const change of changes) {
          const plan = await tx`
            select recurrence_start_local_time::text
            from lifemate.treatment_plans
            where id=${change.treatment_plan_id}::uuid
              and patient_person_id=${ownerPersonId}::uuid
            for update
          `;
          if (
            !plan[0] ||
            localTime(plan[0].recurrence_start_local_time) !==
              localTime(change.proposed_anchor_local_time)
          ) {
            throw new ApiError(
              409,
              "optimization_undo_stale",
              "Schedule changed after apply; automatic undo is no longer safe.",
            );
          }
          await tx`
            update lifemate.treatment_plans
            set recurrence_start_local_time=${
            localTime(change.old_anchor_local_time)
          }::time,
                version=version+1,updated_at_utc=now()
            where id=${change.treatment_plan_id}::uuid
              and patient_person_id=${ownerPersonId}::uuid
          `;
          await tx`
            update lifemate.treatment_schedules
            set local_time=${localTime(change.old_anchor_local_time)}::time
            where treatment_plan_id=${change.treatment_plan_id}::uuid
              and lower(day_of_week)='recurrence'
          `;
          await tx`
            delete from lifemate.dose_occurrences
            where treatment_plan_id=${change.treatment_plan_id}::uuid
              and patient_person_id=${ownerPersonId}::uuid
              and status='Scheduled' and scheduled_at_utc > now()
          `;
        }
      } else {
        await tx`
          update lifemate.dose_occurrence_overrides
          set status='Undone',updated_at_utc=now()
          where run_id=${runId}::uuid and owner_person_id=${ownerPersonId}::uuid
            and status='Active'
        `;
      }
      await tx`
        update lifemate.medication_schedule_optimization_runs
        set status='Undone',undone_at_utc=now(),updated_at_utc=now()
        where id=${runId}::uuid
      `;
      return { runId, status: "undone" };
    });
  }

  async function active(appUserId: string): Promise<Record<string, unknown>[]> {
    const ownerPersonId = await requireSelfPerson(sql, appUserId);
    const rows = await sql`
      select id,mode,algorithm_version,consent_text_version,
             max_variation_minutes,effective_from_local_date,
             effective_until_local_date,status,applied_at_utc,undone_at_utc
      from lifemate.medication_schedule_optimization_runs
      where owner_person_id=${ownerPersonId}::uuid
        and status in ('Applied','Previewed')
      order by created_at_utc desc,id
      limit 20
    `;
    return rows.map((row: Row) => ({
      runId: row.id,
      mode: row.mode,
      algorithmVersion: row.algorithm_version,
      consentTextVersion: row.consent_text_version,
      maxVariationMinutes: row.max_variation_minutes == null
        ? null
        : Number(row.max_variation_minutes),
      effectiveFromLocalDate: String(row.effective_from_local_date).slice(
        0,
        10,
      ),
      effectiveUntilLocalDate: String(row.effective_until_local_date).slice(
        0,
        10,
      ),
      status: String(row.status).toLowerCase(),
      appliedAtUtc: row.applied_at_utc == null
        ? null
        : new Date(row.applied_at_utc).toISOString(),
      undoneAtUtc: row.undone_at_utc == null
        ? null
        : new Date(row.undone_at_utc).toISOString(),
    }));
  }

  return { preview, apply, undo, active };
}

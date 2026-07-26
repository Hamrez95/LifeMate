using System.Text.Json;
using LifeMate.Application.Abstractions;
using LifeMate.Domain.Audit;
using LifeMate.Domain.Common;
using LifeMate.Domain.Treatments;
using LifeMate.Domain.Users;
using Microsoft.EntityFrameworkCore;

namespace LifeMate.Application.Treatments;

public sealed class TreatmentService
{
    private const int MaximumListSize = 100;
    private const int MaximumSchedulesPerPlan = 64;
    private readonly IAppDbContext _db;
    private readonly IClock _clock;
    private readonly ITimeZoneValidator _timeZones;

    public TreatmentService(IAppDbContext db, IClock clock, ITimeZoneValidator timeZones)
    {
        _db = db;
        _clock = clock;
        _timeZones = timeZones;
    }

    public async Task<TreatmentResult<MedicationDto>> CreateMedicationAsync(
        CreateMedicationCommand command,
        CancellationToken cancellationToken)
    {
        var user = await GetCurrentUserAsync(command.Identity, cancellationToken);
        if (user is null) return NotOnboarded<MedicationDto>();

        Medication medication;
        try
        {
            medication = new Medication(
                user.Id,
                command.Name,
                command.StrengthText,
                command.Form,
                command.Notes,
                _clock.UtcNow);
        }
        catch (DomainException exception)
        {
            return Validation<MedicationDto>("invalid_medication", exception.Message);
        }

        _db.Medications.Add(medication);
        AddAudit(user.Id, "medication.created", "medication", medication.Id, medication.Version);
        await _db.SaveChangesAsync(cancellationToken);
        return TreatmentResult<MedicationDto>.Success(Map(medication));
    }

    public async Task<TreatmentResult<IReadOnlyCollection<MedicationDto>>> ListMedicationsAsync(
        TreatmentIdentity identity,
        CancellationToken cancellationToken)
    {
        var user = await GetCurrentUserAsync(identity, cancellationToken);
        if (user is null) return NotOnboarded<IReadOnlyCollection<MedicationDto>>();

        var medications = await _db.Medications
            .AsNoTracking()
            .Where(x => x.OwnerUserId == user.Id)
            .OrderBy(x => x.Name)
            .ThenBy(x => x.Id)
            .Take(MaximumListSize)
            .ToListAsync(cancellationToken);

        return TreatmentResult<IReadOnlyCollection<MedicationDto>>.Success(
            medications.Select(Map).ToArray());
    }

    public async Task<TreatmentResult<MedicationDto>> UpdateMedicationAsync(
        UpdateMedicationCommand command,
        CancellationToken cancellationToken)
    {
        var user = await GetCurrentUserAsync(command.Identity, cancellationToken);
        if (user is null) return NotOnboarded<MedicationDto>();

        var medication = await _db.Medications.SingleOrDefaultAsync(
            x => x.Id == command.MedicationId && x.OwnerUserId == user.Id,
            cancellationToken);
        if (medication is null)
            return NotFound<MedicationDto>("medication_not_found", "Medication was not found.");
        if (medication.Version != command.ExpectedVersion)
            return Conflict<MedicationDto>("stale_medication", "Medication has changed. Refresh and try again.");

        try
        {
            medication.Update(
                command.Name,
                command.StrengthText,
                command.Form,
                command.Notes,
                _clock.UtcNow);
        }
        catch (DomainException exception)
        {
            return Validation<MedicationDto>("invalid_medication", exception.Message);
        }

        AddAudit(user.Id, "medication.updated", "medication", medication.Id, medication.Version);
        try
        {
            await _db.SaveChangesAsync(cancellationToken);
        }
        catch (DbUpdateConcurrencyException)
        {
            return Conflict<MedicationDto>("stale_medication", "Medication has changed. Refresh and try again.");
        }

        return TreatmentResult<MedicationDto>.Success(Map(medication));
    }

    public async Task<TreatmentResult<TreatmentPlanDto>> CreatePlanAsync(
        CreateTreatmentPlanCommand command,
        CancellationToken cancellationToken)
    {
        var user = await GetCurrentUserAsync(command.Identity, cancellationToken);
        if (user is null) return NotOnboarded<TreatmentPlanDto>();

        var medication = await _db.Medications.SingleOrDefaultAsync(
            x => x.Id == command.MedicationId && x.OwnerUserId == user.Id,
            cancellationToken);
        if (medication is null)
            return Validation<TreatmentPlanDto>(
                "invalid_medication",
                "The selected medication does not belong to the authenticated user.");

        var schedulesResult = NormalizeSchedules(command.Schedules);
        if (!schedulesResult.Succeeded)
            return TreatmentResult<TreatmentPlanDto>.Failure(
                schedulesResult.ErrorKind!.Value,
                schedulesResult.ErrorCode!,
                schedulesResult.ErrorMessage!);
        if (!_timeZones.IsValid(command.TimeZone))
            return Validation<TreatmentPlanDto>("invalid_timezone", "Timezone must be a valid IANA timezone identifier.");

        TreatmentPlan plan;
        try
        {
            plan = new TreatmentPlan(
                user.Id,
                medication.Id,
                command.DoseText,
                command.Instructions,
                command.StartDate,
                command.EndDate,
                command.TimeZone,
                _clock.UtcNow);
        }
        catch (DomainException exception)
        {
            return Validation<TreatmentPlanDto>("invalid_treatment_plan", exception.Message);
        }

        var schedules = schedulesResult.Value!
            .Select(x => new TreatmentSchedule(plan.Id, x.DayOfWeek, x.LocalTime, _clock.UtcNow))
            .ToArray();
        _db.TreatmentPlans.Add(plan);
        _db.TreatmentSchedules.AddRange(schedules);
        AddAudit(user.Id, "treatment_plan.created", "treatment_plan", plan.Id, plan.Version);
        await _db.SaveChangesAsync(cancellationToken);

        return TreatmentResult<TreatmentPlanDto>.Success(Map(plan, medication, schedules));
    }

    public async Task<TreatmentResult<IReadOnlyCollection<TreatmentPlanDto>>> ListPlansAsync(
        TreatmentIdentity identity,
        bool includeArchived,
        CancellationToken cancellationToken)
    {
        var user = await GetCurrentUserAsync(identity, cancellationToken);
        if (user is null) return NotOnboarded<IReadOnlyCollection<TreatmentPlanDto>>();

        var query = _db.TreatmentPlans.AsNoTracking().Where(x => x.PatientUserId == user.Id);
        if (!includeArchived) query = query.Where(x => x.Status != TreatmentPlanStatus.Archived);

        var plans = await query
            .OrderByDescending(x => x.UpdatedAtUtc)
            .ThenBy(x => x.Id)
            .Take(MaximumListSize)
            .ToListAsync(cancellationToken);
        var planIds = plans.Select(x => x.Id).ToArray();
        var medicationIds = plans.Select(x => x.MedicationId).Distinct().ToArray();
        var medications = await _db.Medications.AsNoTracking()
            .Where(x => medicationIds.Contains(x.Id))
            .ToDictionaryAsync(x => x.Id, cancellationToken);
        var schedules = await _db.TreatmentSchedules.AsNoTracking()
            .Where(x => planIds.Contains(x.TreatmentPlanId))
            .OrderBy(x => x.DayOfWeek)
            .ThenBy(x => x.LocalTime)
            .ToListAsync(cancellationToken);
        var scheduleLookup = schedules.ToLookup(x => x.TreatmentPlanId);

        var values = plans
            .Select(plan => Map(plan, medications[plan.MedicationId], scheduleLookup[plan.Id]))
            .ToArray();
        return TreatmentResult<IReadOnlyCollection<TreatmentPlanDto>>.Success(values);
    }

    public async Task<TreatmentResult<TreatmentPlanDto>> GetPlanAsync(
        TreatmentIdentity identity,
        Guid planId,
        CancellationToken cancellationToken)
    {
        var user = await GetCurrentUserAsync(identity, cancellationToken);
        if (user is null) return NotOnboarded<TreatmentPlanDto>();
        return await LoadPlanAsync(user.Id, planId, cancellationToken);
    }

    public async Task<TreatmentResult<TreatmentPlanDto>> UpdatePlanAsync(
        UpdateTreatmentPlanCommand command,
        CancellationToken cancellationToken)
    {
        var user = await GetCurrentUserAsync(command.Identity, cancellationToken);
        if (user is null) return NotOnboarded<TreatmentPlanDto>();

        var plan = await _db.TreatmentPlans.SingleOrDefaultAsync(
            x => x.Id == command.TreatmentPlanId && x.PatientUserId == user.Id,
            cancellationToken);
        if (plan is null)
            return NotFound<TreatmentPlanDto>("treatment_plan_not_found", "Treatment plan was not found.");
        if (plan.Version != command.ExpectedVersion)
            return Conflict<TreatmentPlanDto>("stale_treatment_plan", "Treatment plan has changed. Refresh and try again.");

        var medication = await _db.Medications.SingleOrDefaultAsync(
            x => x.Id == command.MedicationId && x.OwnerUserId == user.Id,
            cancellationToken);
        if (medication is null)
            return Validation<TreatmentPlanDto>(
                "invalid_medication",
                "The selected medication does not belong to the authenticated user.");

        var schedulesResult = NormalizeSchedules(command.Schedules);
        if (!schedulesResult.Succeeded)
            return TreatmentResult<TreatmentPlanDto>.Failure(
                schedulesResult.ErrorKind!.Value,
                schedulesResult.ErrorCode!,
                schedulesResult.ErrorMessage!);
        if (!_timeZones.IsValid(command.TimeZone))
            return Validation<TreatmentPlanDto>("invalid_timezone", "Timezone must be a valid IANA timezone identifier.");

        try
        {
            plan.Update(
                medication.Id,
                command.DoseText,
                command.Instructions,
                command.StartDate,
                command.EndDate,
                command.TimeZone,
                _clock.UtcNow);
        }
        catch (DomainException exception)
        {
            return Validation<TreatmentPlanDto>("invalid_treatment_plan", exception.Message);
        }

        var existingSchedules = await _db.TreatmentSchedules
            .Where(x => x.TreatmentPlanId == plan.Id)
            .ToListAsync(cancellationToken);
        _db.TreatmentSchedules.RemoveRange(existingSchedules);
        var replacementSchedules = schedulesResult.Value!
            .Select(x => new TreatmentSchedule(plan.Id, x.DayOfWeek, x.LocalTime, _clock.UtcNow))
            .ToArray();
        _db.TreatmentSchedules.AddRange(replacementSchedules);
        AddAudit(user.Id, "treatment_plan.updated", "treatment_plan", plan.Id, plan.Version);

        try
        {
            await _db.SaveChangesAsync(cancellationToken);
        }
        catch (DbUpdateConcurrencyException)
        {
            return Conflict<TreatmentPlanDto>("stale_treatment_plan", "Treatment plan has changed. Refresh and try again.");
        }

        return TreatmentResult<TreatmentPlanDto>.Success(Map(plan, medication, replacementSchedules));
    }

    public Task<TreatmentResult<TreatmentPlanDto>> PausePlanAsync(
        ChangeTreatmentPlanStatusCommand command,
        CancellationToken cancellationToken) =>
        ChangeStatusAsync(command, "treatment_plan.paused", (plan, now) => plan.Pause(now), cancellationToken);

    public Task<TreatmentResult<TreatmentPlanDto>> ResumePlanAsync(
        ChangeTreatmentPlanStatusCommand command,
        CancellationToken cancellationToken) =>
        ChangeStatusAsync(command, "treatment_plan.resumed", (plan, now) => plan.Resume(now), cancellationToken);

    public Task<TreatmentResult<TreatmentPlanDto>> ArchivePlanAsync(
        ChangeTreatmentPlanStatusCommand command,
        CancellationToken cancellationToken) =>
        ChangeStatusAsync(command, "treatment_plan.archived", (plan, now) => plan.Archive(now), cancellationToken);

    private async Task<TreatmentResult<TreatmentPlanDto>> ChangeStatusAsync(
        ChangeTreatmentPlanStatusCommand command,
        string auditAction,
        Func<TreatmentPlan, DateTime, bool> transition,
        CancellationToken cancellationToken)
    {
        var user = await GetCurrentUserAsync(command.Identity, cancellationToken);
        if (user is null) return NotOnboarded<TreatmentPlanDto>();

        var plan = await _db.TreatmentPlans.SingleOrDefaultAsync(
            x => x.Id == command.TreatmentPlanId && x.PatientUserId == user.Id,
            cancellationToken);
        if (plan is null)
            return NotFound<TreatmentPlanDto>("treatment_plan_not_found", "Treatment plan was not found.");
        if (plan.Version != command.ExpectedVersion)
            return Conflict<TreatmentPlanDto>("stale_treatment_plan", "Treatment plan has changed. Refresh and try again.");

        try
        {
            if (transition(plan, _clock.UtcNow))
                AddAudit(user.Id, auditAction, "treatment_plan", plan.Id, plan.Version);
        }
        catch (DomainException exception)
        {
            return Validation<TreatmentPlanDto>("invalid_treatment_plan_transition", exception.Message);
        }

        try
        {
            await _db.SaveChangesAsync(cancellationToken);
        }
        catch (DbUpdateConcurrencyException)
        {
            return Conflict<TreatmentPlanDto>("stale_treatment_plan", "Treatment plan has changed. Refresh and try again.");
        }

        return await LoadPlanAsync(user.Id, plan.Id, cancellationToken);
    }

    private async Task<TreatmentResult<TreatmentPlanDto>> LoadPlanAsync(
        Guid userId,
        Guid planId,
        CancellationToken cancellationToken)
    {
        var plan = await _db.TreatmentPlans.AsNoTracking().SingleOrDefaultAsync(
            x => x.Id == planId && x.PatientUserId == userId,
            cancellationToken);
        if (plan is null)
            return NotFound<TreatmentPlanDto>("treatment_plan_not_found", "Treatment plan was not found.");

        var medication = await _db.Medications.AsNoTracking().SingleAsync(
            x => x.Id == plan.MedicationId,
            cancellationToken);
        var schedules = await _db.TreatmentSchedules.AsNoTracking()
            .Where(x => x.TreatmentPlanId == plan.Id)
            .OrderBy(x => x.DayOfWeek)
            .ThenBy(x => x.LocalTime)
            .ToListAsync(cancellationToken);
        return TreatmentResult<TreatmentPlanDto>.Success(Map(plan, medication, schedules));
    }

    private TreatmentResult<IReadOnlyCollection<TreatmentScheduleInput>> NormalizeSchedules(
        IReadOnlyCollection<TreatmentScheduleInput>? schedules)
    {
        if (schedules is null || schedules.Count == 0)
            return Validation<IReadOnlyCollection<TreatmentScheduleInput>>(
                "schedule_required",
                "At least one weekly treatment schedule is required.");
        if (schedules.Count > MaximumSchedulesPerPlan)
            return Validation<IReadOnlyCollection<TreatmentScheduleInput>>(
                "too_many_schedules",
                $"A treatment plan supports at most {MaximumSchedulesPerPlan} schedules.");

        var normalized = new List<TreatmentScheduleInput>(schedules.Count);
        var keys = new HashSet<(DayOfWeek Day, TimeOnly Time)>();
        foreach (var schedule in schedules)
        {
            if (!Enum.IsDefined(schedule.DayOfWeek))
                return Validation<IReadOnlyCollection<TreatmentScheduleInput>>(
                    "invalid_schedule_day",
                    "Treatment schedule contains an invalid weekday.");

            var localTime = new TimeOnly(schedule.LocalTime.Hour, schedule.LocalTime.Minute);
            var key = (schedule.DayOfWeek, localTime);
            if (!keys.Add(key))
                return Validation<IReadOnlyCollection<TreatmentScheduleInput>>(
                    "duplicate_schedule",
                    "A weekday and local time can appear only once in a treatment plan.");
            normalized.Add(new TreatmentScheduleInput(schedule.DayOfWeek, localTime));
        }

        return TreatmentResult<IReadOnlyCollection<TreatmentScheduleInput>>.Success(normalized);
    }

    private async Task<AppUser?> GetCurrentUserAsync(
        TreatmentIdentity identity,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(identity.AuthSubject)) return null;
        var subject = identity.AuthSubject.Trim();
        return await _db.Users.SingleOrDefaultAsync(
            x => x.AuthSubject == subject && x.Status == AppUserStatus.Active,
            cancellationToken);
    }

    private void AddAudit(
        Guid actorUserId,
        string action,
        string resourceType,
        Guid resourceId,
        int version)
    {
        _db.AuditLogs.Add(new AuditLog(
            actorUserId,
            action,
            resourceType,
            resourceId,
            JsonSerializer.Serialize(new { version }),
            _clock.UtcNow));
    }

    private static MedicationDto Map(Medication medication) => new(
        medication.Id,
        medication.Name,
        medication.StrengthText,
        medication.Form,
        medication.Notes,
        medication.Version,
        medication.CreatedAtUtc,
        medication.UpdatedAtUtc);

    private static TreatmentPlanDto Map(
        TreatmentPlan plan,
        Medication medication,
        IEnumerable<TreatmentSchedule> schedules) => new(
        plan.Id,
        plan.PatientUserId,
        Map(medication),
        plan.DoseText,
        plan.Instructions,
        plan.StartDate,
        plan.EndDate,
        plan.TimeZone,
        plan.Status.ToString().ToLowerInvariant(),
        plan.Version,
        schedules.Select(x => new TreatmentScheduleDto(x.Id, x.DayOfWeek, x.LocalTime)).ToArray(),
        plan.CreatedAtUtc,
        plan.UpdatedAtUtc);

    private static TreatmentResult<T> NotOnboarded<T>() =>
        NotFound<T>("not_onboarded", "Bootstrap is required before managing treatment data.");

    private static TreatmentResult<T> Validation<T>(string code, string message) =>
        TreatmentResult<T>.Failure(TreatmentErrorKind.Validation, code, message);

    private static TreatmentResult<T> NotFound<T>(string code, string message) =>
        TreatmentResult<T>.Failure(TreatmentErrorKind.NotFound, code, message);

    private static TreatmentResult<T> Conflict<T>(string code, string message) =>
        TreatmentResult<T>.Failure(TreatmentErrorKind.Conflict, code, message);
}

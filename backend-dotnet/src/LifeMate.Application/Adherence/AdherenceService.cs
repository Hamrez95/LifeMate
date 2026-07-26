using System.Text.Json;
using LifeMate.Application.Abstractions;
using LifeMate.Domain.Adherence;
using LifeMate.Domain.Audit;
using LifeMate.Domain.Common;
using LifeMate.Domain.Treatments;
using LifeMate.Domain.Users;
using Microsoft.EntityFrameworkCore;

namespace LifeMate.Application.Adherence;

public sealed class AdherenceService
{
    private static readonly TimeSpan MissedGracePeriod = TimeSpan.FromMinutes(60);
    private readonly IAppDbContext _db;
    private readonly IClock _clock;

    public AdherenceService(IAppDbContext db, IClock clock)
    {
        _db = db;
        _clock = clock;
    }

    public async Task<AdherenceResult<IReadOnlyCollection<DoseOccurrenceDto>>> ListAsync(
        ListDoseOccurrencesCommand command,
        CancellationToken cancellationToken)
    {
        var user = await GetCurrentUserAsync(command.Identity, cancellationToken);
        if (user is null) return NotOnboarded<IReadOnlyCollection<DoseOccurrenceDto>>();

        if (command.ToDate < command.FromDate)
            return Validation<IReadOnlyCollection<DoseOccurrenceDto>>(
                "invalid_range",
                "Dose range end cannot be before its start.");
        if (command.ToDate.DayNumber - command.FromDate.DayNumber + 1 > DoseOccurrenceGenerator.MaximumRangeDays)
            return Validation<IReadOnlyCollection<DoseOccurrenceDto>>(
                "range_too_large",
                $"Dose range cannot exceed {DoseOccurrenceGenerator.MaximumRangeDays} days.");

        var plans = await _db.TreatmentPlans
            .AsNoTracking()
            .Where(x => x.PatientUserId == user.Id
                && x.StartDate <= command.ToDate
                && (!x.EndDate.HasValue || x.EndDate.Value >= command.FromDate))
            .ToListAsync(cancellationToken);
        var planIds = plans.Select(x => x.Id).ToArray();
        var schedules = await _db.TreatmentSchedules
            .AsNoTracking()
            .Where(x => planIds.Contains(x.TreatmentPlanId))
            .ToListAsync(cancellationToken);

        var desired = new Dictionary<(Guid ScheduleId, DateTime ScheduledAtUtc), GeneratedDoseOccurrence>();
        try
        {
            foreach (var plan in plans)
            {
                var generated = DoseOccurrenceGenerator.Generate(
                    plan,
                    schedules.Where(x => x.TreatmentPlanId == plan.Id).ToArray(),
                    command.FromDate,
                    command.ToDate);
                foreach (var value in generated.Occurrences)
                    desired[(value.TreatmentScheduleId, value.ScheduledAtUtc)] = value;
            }
        }
        catch (DomainException exception)
        {
            return Validation<IReadOnlyCollection<DoseOccurrenceDto>>(
                "occurrence_generation_failed",
                exception.Message);
        }

        var occurrences = await _db.DoseOccurrences
            .Where(x => x.PatientUserId == user.Id
                && x.ScheduledLocalDate >= command.FromDate
                && x.ScheduledLocalDate <= command.ToDate)
            .ToListAsync(cancellationToken);
        var existingKeys = occurrences
            .Select(x => (x.TreatmentScheduleId, x.ScheduledAtUtc))
            .ToHashSet();

        foreach (var item in desired.Values.Where(x =>
                     !existingKeys.Contains((x.TreatmentScheduleId, x.ScheduledAtUtc))))
        {
            var occurrence = new DoseOccurrence(
                user.Id,
                item.TreatmentPlanId,
                item.TreatmentScheduleId,
                item.ScheduledAtUtc,
                item.LocalDate,
                item.LocalTime,
                item.TimeZone,
                _clock.UtcNow);
            _db.DoseOccurrences.Add(occurrence);
            occurrences.Add(occurrence);
        }

        var now = _clock.UtcNow;
        foreach (var occurrence in occurrences)
        {
            var belongsToCurrentSchedule = desired.ContainsKey(
                (occurrence.TreatmentScheduleId, occurrence.ScheduledAtUtc));
            if (belongsToCurrentSchedule
                && occurrence.Status == DoseOccurrenceStatus.Scheduled
                && occurrence.ScheduledAtUtc.Add(MissedGracePeriod) <= now)
            {
                occurrence.MarkMissed(now);
            }
        }

        try
        {
            await _db.SaveChangesAsync(cancellationToken);
        }
        catch (DbUpdateException)
        {
            // Deterministic ids and the database unique key make concurrent materialization safe.
            // If another request won the race, return the committed projection; otherwise preserve
            // the original database failure instead of masking an operational defect.
            var committed = await _db.DoseOccurrences
                .AsNoTracking()
                .Where(x => x.PatientUserId == user.Id
                    && x.ScheduledLocalDate >= command.FromDate
                    && x.ScheduledLocalDate <= command.ToDate)
                .ToListAsync(cancellationToken);
            var committedKeys = committed
                .Select(x => (x.TreatmentScheduleId, x.ScheduledAtUtc))
                .ToHashSet();
            if (!desired.Keys.All(committedKeys.Contains)) throw;

            return AdherenceResult<IReadOnlyCollection<DoseOccurrenceDto>>.Success(
                Visible(committed, desired)
                    .OrderBy(x => x.ScheduledAtUtc)
                    .ThenBy(x => x.Id)
                    .Select(Map)
                    .ToArray());
        }

        return AdherenceResult<IReadOnlyCollection<DoseOccurrenceDto>>.Success(
            Visible(occurrences, desired)
                .OrderBy(x => x.ScheduledAtUtc)
                .ThenBy(x => x.Id)
                .Select(Map)
                .ToArray());
    }

    public async Task<AdherenceResult<DoseOccurrenceDto>> ReportAsync(
        ReportDoseOccurrenceCommand command,
        CancellationToken cancellationToken)
    {
        var user = await GetCurrentUserAsync(command.Identity, cancellationToken);
        if (user is null) return NotOnboarded<DoseOccurrenceDto>();
        if (command.ClientRequestId == Guid.Empty)
            return Validation<DoseOccurrenceDto>("idempotency_key_required", "Client request id is required.");
        if (command.ExpectedVersion < 1)
            return Validation<DoseOccurrenceDto>("invalid_version", "Occurrence version must be positive.");
        if (command.OccurredAtUtc.Kind != DateTimeKind.Utc)
            return Validation<DoseOccurrenceDto>("invalid_timestamp", "Occurred-at timestamp must be UTC.");
        if (command.OccurredAtUtc > _clock.UtcNow.AddMinutes(5))
            return Validation<DoseOccurrenceDto>("future_timestamp", "Occurred-at timestamp cannot be in the future.");

        var priorEvent = await _db.DoseAdherenceEvents
            .AsNoTracking()
            .SingleOrDefaultAsync(
                x => x.ActorUserId == user.Id && x.ClientRequestId == command.ClientRequestId,
                cancellationToken);
        if (priorEvent is not null)
        {
            if (priorEvent.OccurrenceId != command.OccurrenceId
                || priorEvent.ResultingStatus != command.Status)
            {
                return Conflict<DoseOccurrenceDto>(
                    "idempotency_key_reused",
                    "Client request id was already used for a different report.");
            }

            var replay = await _db.DoseOccurrences
                .AsNoTracking()
                .SingleOrDefaultAsync(
                    x => x.Id == command.OccurrenceId && x.PatientUserId == user.Id,
                    cancellationToken);
            return replay is null
                ? NotFound<DoseOccurrenceDto>("dose_not_found", "Dose occurrence was not found.")
                : AdherenceResult<DoseOccurrenceDto>.Success(Map(replay));
        }

        var occurrence = await _db.DoseOccurrences.SingleOrDefaultAsync(
            x => x.Id == command.OccurrenceId && x.PatientUserId == user.Id,
            cancellationToken);
        if (occurrence is null)
            return NotFound<DoseOccurrenceDto>("dose_not_found", "Dose occurrence was not found.");
        if (occurrence.Version != command.ExpectedVersion)
            return Conflict<DoseOccurrenceDto>("stale_dose", "Dose occurrence has changed. Refresh and try again.");

        var previousStatus = occurrence.Status;
        DoseAdherenceEventType? eventType;
        try
        {
            eventType = occurrence.ApplyPatientReport(command.Status, command.OccurredAtUtc, _clock.UtcNow);
        }
        catch (DomainException exception)
        {
            return Validation<DoseOccurrenceDto>("invalid_dose_report", exception.Message);
        }

        if (eventType is not null)
        {
            _db.DoseAdherenceEvents.Add(new DoseAdherenceEvent(
                occurrence.Id,
                user.Id,
                command.ClientRequestId,
                eventType.Value,
                previousStatus,
                occurrence.Status,
                command.OccurredAtUtc,
                _clock.UtcNow));
            AddAudit(user.Id, "dose.reported", occurrence.Id, occurrence.Version);
        }

        try
        {
            await _db.SaveChangesAsync(cancellationToken);
        }
        catch (DbUpdateConcurrencyException)
        {
            return Conflict<DoseOccurrenceDto>("stale_dose", "Dose occurrence has changed. Refresh and try again.");
        }
        catch (DbUpdateException)
        {
            return Conflict<DoseOccurrenceDto>(
                "duplicate_report",
                "This dose report was already processed. Refresh to read the current state.");
        }

        return AdherenceResult<DoseOccurrenceDto>.Success(Map(occurrence));
    }

    private async Task<AppUser?> GetCurrentUserAsync(
        AdherenceIdentity identity,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(identity.AuthSubject)) return null;
        var subject = identity.AuthSubject.Trim();
        return await _db.Users.SingleOrDefaultAsync(
            x => x.AuthSubject == subject && x.Status == AppUserStatus.Active,
            cancellationToken);
    }

    private void AddAudit(Guid actorUserId, string action, Guid resourceId, int version)
    {
        _db.AuditLogs.Add(new AuditLog(
            actorUserId,
            action,
            "dose_occurrence",
            resourceId,
            JsonSerializer.Serialize(new { version }),
            _clock.UtcNow));
    }

    private static IEnumerable<DoseOccurrence> Visible(
        IEnumerable<DoseOccurrence> occurrences,
        IReadOnlyDictionary<(Guid ScheduleId, DateTime ScheduledAtUtc), GeneratedDoseOccurrence> desired) =>
        occurrences.Where(x =>
            desired.ContainsKey((x.TreatmentScheduleId, x.ScheduledAtUtc))
            || x.Status is DoseOccurrenceStatus.Taken
                or DoseOccurrenceStatus.Skipped
                or DoseOccurrenceStatus.Missed);

    private static DoseOccurrenceDto Map(DoseOccurrence value) => new(
        value.Id,
        value.TreatmentPlanId,
        value.TreatmentScheduleId,
        value.ScheduledAtUtc,
        value.ScheduledLocalDate,
        value.ScheduledLocalTime,
        value.TimeZone,
        value.Status.ToString().ToLowerInvariant(),
        value.RespondedAtUtc,
        value.Version);

    private static AdherenceResult<T> Validation<T>(string code, string message) =>
        AdherenceResult<T>.Failure(AdherenceErrorKind.Validation, code, message);

    private static AdherenceResult<T> NotFound<T>(string code, string message) =>
        AdherenceResult<T>.Failure(AdherenceErrorKind.NotFound, code, message);

    private static AdherenceResult<T> Conflict<T>(string code, string message) =>
        AdherenceResult<T>.Failure(AdherenceErrorKind.Conflict, code, message);

    private static AdherenceResult<T> NotOnboarded<T>() =>
        NotFound<T>("user_not_onboarded", "Authenticated user has not completed bootstrap.");
}

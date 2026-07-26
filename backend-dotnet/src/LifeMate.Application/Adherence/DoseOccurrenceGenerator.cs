using LifeMate.Domain.Common;
using LifeMate.Domain.Treatments;

namespace LifeMate.Application.Adherence;

public sealed record GeneratedDoseOccurrence(
    Guid TreatmentPlanId,
    Guid TreatmentScheduleId,
    DateOnly LocalDate,
    TimeOnly LocalTime,
    DateTime ScheduledAtUtc,
    string TimeZone);

public sealed record DoseOccurrenceGenerationResult(
    IReadOnlyList<GeneratedDoseOccurrence> Occurrences,
    int SkippedInvalidLocalTimes);

public static class DoseOccurrenceGenerator
{
    public const int MaximumRangeDays = 31;

    public static DoseOccurrenceGenerationResult Generate(
        TreatmentPlan plan,
        IReadOnlyCollection<TreatmentSchedule> schedules,
        DateOnly fromDate,
        DateOnly toDate)
    {
        ArgumentNullException.ThrowIfNull(plan);
        ArgumentNullException.ThrowIfNull(schedules);

        if (toDate < fromDate)
            throw new DomainException("Occurrence range end cannot be before its start.");

        var rangeDays = toDate.DayNumber - fromDate.DayNumber + 1;
        if (rangeDays > MaximumRangeDays)
            throw new DomainException($"Occurrence range cannot exceed {MaximumRangeDays} days.");

        TimeZoneInfo timeZone;
        try
        {
            timeZone = TimeZoneInfo.FindSystemTimeZoneById(plan.TimeZone);
        }
        catch (TimeZoneNotFoundException)
        {
            throw new DomainException("Treatment timezone is not available on this server.");
        }
        catch (InvalidTimeZoneException)
        {
            throw new DomainException("Treatment timezone configuration is invalid.");
        }

        if (plan.Status != TreatmentPlanStatus.Active)
            return new DoseOccurrenceGenerationResult([], 0);

        var effectiveFrom = fromDate < plan.StartDate ? plan.StartDate : fromDate;
        var effectiveTo = plan.EndDate.HasValue && toDate > plan.EndDate.Value
            ? plan.EndDate.Value
            : toDate;

        if (effectiveTo < effectiveFrom)
            return new DoseOccurrenceGenerationResult([], 0);

        var uniqueSchedules = schedules
            .Where(x => x.TreatmentPlanId == plan.Id)
            .GroupBy(x => new { x.DayOfWeek, x.LocalTime })
            .Select(x => x.OrderBy(item => item.Id).First())
            .OrderBy(x => x.DayOfWeek)
            .ThenBy(x => x.LocalTime)
            .ToArray();

        var results = new List<GeneratedDoseOccurrence>();
        var skippedInvalid = 0;

        for (var date = effectiveFrom; date <= effectiveTo; date = date.AddDays(1))
        {
            foreach (var schedule in uniqueSchedules.Where(x => x.DayOfWeek == date.DayOfWeek))
            {
                var local = date.ToDateTime(schedule.LocalTime, DateTimeKind.Unspecified);

                // Spring-forward gaps do not represent a real instant. We skip them explicitly;
                // a later worker can surface this as an operational warning instead of inventing a dose time.
                if (timeZone.IsInvalidTime(local))
                {
                    skippedInvalid++;
                    continue;
                }

                DateTime scheduledAtUtc;
                if (timeZone.IsAmbiguousTime(local))
                {
                    // Fall-back creates two possible instants. Choose the earlier UTC instant so one
                    // deterministic occurrence is produced and retries always generate the same key.
                    scheduledAtUtc = timeZone.GetAmbiguousTimeOffsets(local)
                        .Select(offset => DateTime.SpecifyKind(local - offset, DateTimeKind.Utc))
                        .Min();
                }
                else
                {
                    scheduledAtUtc = TimeZoneInfo.ConvertTimeToUtc(local, timeZone);
                }

                results.Add(new GeneratedDoseOccurrence(
                    plan.Id,
                    schedule.Id,
                    date,
                    schedule.LocalTime,
                    scheduledAtUtc,
                    plan.TimeZone));
            }
        }

        return new DoseOccurrenceGenerationResult(
            results.OrderBy(x => x.ScheduledAtUtc).ThenBy(x => x.TreatmentScheduleId).ToArray(),
            skippedInvalid);
    }
}

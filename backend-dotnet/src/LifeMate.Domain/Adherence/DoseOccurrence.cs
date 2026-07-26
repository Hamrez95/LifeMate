using LifeMate.Domain.Common;

namespace LifeMate.Domain.Adherence;

public sealed class DoseOccurrence
{
    private DoseOccurrence()
    {
        TimeZone = string.Empty;
    }

    public DoseOccurrence(
        Guid patientUserId,
        Guid treatmentPlanId,
        Guid treatmentScheduleId,
        DateTime scheduledAtUtc,
        DateOnly scheduledLocalDate,
        TimeOnly scheduledLocalTime,
        string timeZone,
        DateTime utcNow)
    {
        if (patientUserId == Guid.Empty) throw new DomainException("Patient is required.");
        if (treatmentPlanId == Guid.Empty) throw new DomainException("Treatment plan is required.");
        if (treatmentScheduleId == Guid.Empty) throw new DomainException("Treatment schedule is required.");
        EnsureUtc(scheduledAtUtc);
        EnsureUtc(utcNow);
        if (string.IsNullOrWhiteSpace(timeZone) || timeZone.Trim().Length > 64)
            throw new DomainException("Occurrence timezone is required.");

        Id = Guid.NewGuid();
        PatientUserId = patientUserId;
        TreatmentPlanId = treatmentPlanId;
        TreatmentScheduleId = treatmentScheduleId;
        ScheduledAtUtc = scheduledAtUtc;
        ScheduledLocalDate = scheduledLocalDate;
        ScheduledLocalTime = new TimeOnly(scheduledLocalTime.Hour, scheduledLocalTime.Minute);
        TimeZone = timeZone.Trim();
        Status = DoseOccurrenceStatus.Scheduled;
        Version = 1;
        CreatedAtUtc = utcNow;
        UpdatedAtUtc = utcNow;
    }

    public Guid Id { get; private set; }
    public Guid PatientUserId { get; private set; }
    public Guid TreatmentPlanId { get; private set; }
    public Guid TreatmentScheduleId { get; private set; }
    public DateTime ScheduledAtUtc { get; private set; }
    public DateOnly ScheduledLocalDate { get; private set; }
    public TimeOnly ScheduledLocalTime { get; private set; }
    public string TimeZone { get; private set; }
    public DoseOccurrenceStatus Status { get; private set; }
    public DateTime? RespondedAtUtc { get; private set; }
    public int Version { get; private set; }
    public DateTime CreatedAtUtc { get; private set; }
    public DateTime UpdatedAtUtc { get; private set; }

    public DoseAdherenceEventType? ApplyPatientReport(
        DoseOccurrenceStatus targetStatus,
        DateTime respondedAtUtc,
        DateTime utcNow)
    {
        EnsureUtc(respondedAtUtc);
        EnsureUtc(utcNow);
        if (targetStatus is not DoseOccurrenceStatus.Taken and not DoseOccurrenceStatus.Skipped)
            throw new DomainException("Patient report must be taken or skipped.");
        if (Status == DoseOccurrenceStatus.Cancelled)
            throw new DomainException("A cancelled dose cannot be reported.");
        if (Status == targetStatus) return null;

        var eventType = Status == DoseOccurrenceStatus.Scheduled
            ? targetStatus == DoseOccurrenceStatus.Taken
                ? DoseAdherenceEventType.Taken
                : DoseAdherenceEventType.Skipped
            : DoseAdherenceEventType.Corrected;

        Status = targetStatus;
        RespondedAtUtc = respondedAtUtc;
        Touch(utcNow);
        return eventType;
    }

    public bool MarkMissed(DateTime utcNow)
    {
        EnsureUtc(utcNow);
        if (Status != DoseOccurrenceStatus.Scheduled) return false;
        Status = DoseOccurrenceStatus.Missed;
        Touch(utcNow);
        return true;
    }

    public bool Cancel(DateTime utcNow)
    {
        EnsureUtc(utcNow);
        if (Status == DoseOccurrenceStatus.Cancelled) return false;
        if (Status is DoseOccurrenceStatus.Taken or DoseOccurrenceStatus.Skipped)
            throw new DomainException("A reported dose cannot be cancelled.");

        Status = DoseOccurrenceStatus.Cancelled;
        Touch(utcNow);
        return true;
    }

    private void Touch(DateTime utcNow)
    {
        Version++;
        UpdatedAtUtc = utcNow;
    }

    private static DateTime EnsureUtc(DateTime value) =>
        value.Kind == DateTimeKind.Utc
            ? value
            : throw new DomainException("Timestamps must be UTC.");
}

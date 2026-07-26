using LifeMate.Domain.Common;

namespace LifeMate.Domain.Treatments;

public sealed class TreatmentSchedule
{
    private TreatmentSchedule() { }

    public TreatmentSchedule(
        Guid treatmentPlanId,
        DayOfWeek dayOfWeek,
        TimeOnly localTime,
        DateTime utcNow)
    {
        if (treatmentPlanId == Guid.Empty) throw new DomainException("Treatment plan is required.");
        if (!Enum.IsDefined(dayOfWeek)) throw new DomainException("Schedule day is invalid.");
        EnsureUtc(utcNow);

        Id = Guid.NewGuid();
        TreatmentPlanId = treatmentPlanId;
        DayOfWeek = dayOfWeek;
        LocalTime = new TimeOnly(localTime.Hour, localTime.Minute);
        CreatedAtUtc = utcNow;
    }

    public Guid Id { get; private set; }
    public Guid TreatmentPlanId { get; private set; }
    public DayOfWeek DayOfWeek { get; private set; }
    public TimeOnly LocalTime { get; private set; }
    public DateTime CreatedAtUtc { get; private set; }

    private static DateTime EnsureUtc(DateTime value) =>
        value.Kind == DateTimeKind.Utc
            ? value
            : throw new DomainException("Timestamps must be UTC.");
}

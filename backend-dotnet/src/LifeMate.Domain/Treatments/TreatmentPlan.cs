using LifeMate.Domain.Common;

namespace LifeMate.Domain.Treatments;

public sealed class TreatmentPlan
{
    private TreatmentPlan()
    {
        DoseText = string.Empty;
        TimeZone = string.Empty;
    }

    public TreatmentPlan(
        Guid patientUserId,
        Guid medicationId,
        string doseText,
        string? instructions,
        DateOnly startDate,
        DateOnly? endDate,
        string timeZone,
        DateTime utcNow)
    {
        if (patientUserId == Guid.Empty) throw new DomainException("Patient is required.");
        if (medicationId == Guid.Empty) throw new DomainException("Medication is required.");
        Validate(doseText, instructions, startDate, endDate, timeZone);
        EnsureUtc(utcNow);

        Id = Guid.NewGuid();
        PatientUserId = patientUserId;
        MedicationId = medicationId;
        DoseText = doseText.Trim();
        Instructions = NormalizeOptional(instructions);
        StartDate = startDate;
        EndDate = endDate;
        TimeZone = timeZone.Trim();
        Status = TreatmentPlanStatus.Active;
        Version = 1;
        CreatedAtUtc = utcNow;
        UpdatedAtUtc = utcNow;
    }

    public Guid Id { get; private set; }
    public Guid PatientUserId { get; private set; }
    public Guid MedicationId { get; private set; }
    public string DoseText { get; private set; }
    public string? Instructions { get; private set; }
    public DateOnly StartDate { get; private set; }
    public DateOnly? EndDate { get; private set; }
    public string TimeZone { get; private set; }
    public TreatmentPlanStatus Status { get; private set; }
    public int Version { get; private set; }
    public DateTime CreatedAtUtc { get; private set; }
    public DateTime UpdatedAtUtc { get; private set; }

    public void Update(
        Guid medicationId,
        string doseText,
        string? instructions,
        DateOnly startDate,
        DateOnly? endDate,
        string timeZone,
        DateTime utcNow)
    {
        if (Status == TreatmentPlanStatus.Archived)
            throw new DomainException("An archived treatment plan cannot be edited.");
        if (medicationId == Guid.Empty) throw new DomainException("Medication is required.");
        Validate(doseText, instructions, startDate, endDate, timeZone);
        EnsureUtc(utcNow);

        MedicationId = medicationId;
        DoseText = doseText.Trim();
        Instructions = NormalizeOptional(instructions);
        StartDate = startDate;
        EndDate = endDate;
        TimeZone = timeZone.Trim();
        Touch(utcNow);
    }

    public bool Pause(DateTime utcNow)
    {
        EnsureUtc(utcNow);
        if (Status == TreatmentPlanStatus.Archived)
            throw new DomainException("An archived treatment plan cannot be paused.");
        if (Status == TreatmentPlanStatus.Paused) return false;

        Status = TreatmentPlanStatus.Paused;
        Touch(utcNow);
        return true;
    }

    public bool Resume(DateTime utcNow)
    {
        EnsureUtc(utcNow);
        if (Status == TreatmentPlanStatus.Archived)
            throw new DomainException("An archived treatment plan cannot be resumed.");
        if (Status == TreatmentPlanStatus.Active) return false;

        Status = TreatmentPlanStatus.Active;
        Touch(utcNow);
        return true;
    }

    public bool Archive(DateTime utcNow)
    {
        EnsureUtc(utcNow);
        if (Status == TreatmentPlanStatus.Archived) return false;

        Status = TreatmentPlanStatus.Archived;
        Touch(utcNow);
        return true;
    }

    private void Touch(DateTime utcNow)
    {
        Version++;
        UpdatedAtUtc = utcNow;
    }

    private static void Validate(
        string doseText,
        string? instructions,
        DateOnly startDate,
        DateOnly? endDate,
        string timeZone)
    {
        if (string.IsNullOrWhiteSpace(doseText) || doseText.Trim().Length > 80)
            throw new DomainException("Dose instructions are required and must be 80 characters or fewer.");
        if (instructions?.Trim().Length > 500)
            throw new DomainException("Treatment instructions must be 500 characters or fewer.");
        if (endDate.HasValue && endDate.Value < startDate)
            throw new DomainException("Treatment end date cannot be before the start date.");
        if (string.IsNullOrWhiteSpace(timeZone) || timeZone.Trim().Length > 64)
            throw new DomainException("A valid treatment timezone is required.");
    }

    private static string? NormalizeOptional(string? value) =>
        string.IsNullOrWhiteSpace(value) ? null : value.Trim();

    private static DateTime EnsureUtc(DateTime value) =>
        value.Kind == DateTimeKind.Utc
            ? value
            : throw new DomainException("Timestamps must be UTC.");
}

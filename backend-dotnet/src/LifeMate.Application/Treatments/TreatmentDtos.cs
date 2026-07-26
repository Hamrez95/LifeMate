using LifeMate.Domain.Treatments;

namespace LifeMate.Application.Treatments;

public sealed record TreatmentIdentity(string AuthSubject);

public sealed record CreateMedicationCommand(
    TreatmentIdentity Identity,
    string Name,
    string? StrengthText,
    string? Form,
    string? Notes);

public sealed record UpdateMedicationCommand(
    TreatmentIdentity Identity,
    Guid MedicationId,
    int ExpectedVersion,
    string Name,
    string? StrengthText,
    string? Form,
    string? Notes);

public sealed record TreatmentScheduleInput(
    DayOfWeek DayOfWeek,
    TimeOnly LocalTime);

public sealed record CreateTreatmentPlanCommand(
    TreatmentIdentity Identity,
    Guid MedicationId,
    string DoseText,
    string? Instructions,
    DateOnly StartDate,
    DateOnly? EndDate,
    string TimeZone,
    IReadOnlyCollection<TreatmentScheduleInput> Schedules);

public sealed record UpdateTreatmentPlanCommand(
    TreatmentIdentity Identity,
    Guid TreatmentPlanId,
    int ExpectedVersion,
    Guid MedicationId,
    string DoseText,
    string? Instructions,
    DateOnly StartDate,
    DateOnly? EndDate,
    string TimeZone,
    IReadOnlyCollection<TreatmentScheduleInput> Schedules);

public sealed record ChangeTreatmentPlanStatusCommand(
    TreatmentIdentity Identity,
    Guid TreatmentPlanId,
    int ExpectedVersion);

public sealed record MedicationDto(
    Guid Id,
    string Name,
    string? StrengthText,
    string? Form,
    string? Notes,
    int Version,
    DateTime CreatedAtUtc,
    DateTime UpdatedAtUtc);

public sealed record TreatmentScheduleDto(
    Guid Id,
    DayOfWeek DayOfWeek,
    TimeOnly LocalTime);

public sealed record TreatmentPlanDto(
    Guid Id,
    Guid PatientUserId,
    MedicationDto Medication,
    string DoseText,
    string? Instructions,
    DateOnly StartDate,
    DateOnly? EndDate,
    string TimeZone,
    string Status,
    int Version,
    IReadOnlyCollection<TreatmentScheduleDto> Schedules,
    DateTime CreatedAtUtc,
    DateTime UpdatedAtUtc);

public enum TreatmentErrorKind
{
    Validation,
    NotFound,
    Conflict
}

public sealed record TreatmentResult<T>(
    bool Succeeded,
    T? Value,
    TreatmentErrorKind? ErrorKind,
    string? ErrorCode,
    string? ErrorMessage)
{
    public static TreatmentResult<T> Success(T value) => new(true, value, null, null, null);

    public static TreatmentResult<T> Failure(
        TreatmentErrorKind kind,
        string code,
        string message) => new(false, default, kind, code, message);
}

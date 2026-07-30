using LifeMate.Domain.Adherence;

namespace LifeMate.Application.Adherence;

public sealed record AdherenceIdentity(string AuthSubject);

public sealed record ListDoseOccurrencesCommand(
    AdherenceIdentity Identity,
    DateOnly FromDate,
    DateOnly ToDate);

public sealed record ListCareRecipientDoseOccurrencesCommand(
    AdherenceIdentity Identity,
    Guid PatientUserId,
    DateOnly FromDate,
    DateOnly ToDate);

public sealed record ReportDoseOccurrenceCommand(
    AdherenceIdentity Identity,
    Guid OccurrenceId,
    Guid ClientRequestId,
    int ExpectedVersion,
    DoseOccurrenceStatus Status,
    DateTime OccurredAtUtc);

public sealed record DoseOccurrenceDto(
    Guid Id,
    Guid TreatmentPlanId,
    Guid TreatmentScheduleId,
    DateTime ScheduledAtUtc,
    DateOnly ScheduledLocalDate,
    TimeOnly ScheduledLocalTime,
    string TimeZone,
    string Status,
    DateTime? RespondedAtUtc,
    int Version);

public sealed record CareRecipientDoseOccurrenceDto(
    Guid Id,
    Guid TreatmentPlanId,
    Guid TreatmentScheduleId,
    string MedicationName,
    string DoseText,
    DateTime ScheduledAtUtc,
    DateOnly ScheduledLocalDate,
    TimeOnly ScheduledLocalTime,
    string TimeZone,
    string Status,
    DateTime? RespondedAtUtc,
    int Version);

public enum AdherenceErrorKind
{
    Validation,
    NotFound,
    Forbidden,
    Conflict
}

public sealed record AdherenceResult<T>(
    bool Succeeded,
    T? Value,
    AdherenceErrorKind? ErrorKind,
    string? ErrorCode,
    string? ErrorMessage)
{
    public static AdherenceResult<T> Success(T value) => new(true, value, null, null, null);

    public static AdherenceResult<T> Failure(
        AdherenceErrorKind kind,
        string code,
        string message) => new(false, default, kind, code, message);
}

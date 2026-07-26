using System.ComponentModel.DataAnnotations;
using LifeMate.Domain.Adherence;
using LifeMate.Domain.Care;

namespace LifeMate.Api.Models;

public sealed record BootstrapUserRequest(
    [property: MaxLength(120)] string? DisplayName,
    [property: Phone, MaxLength(32)] string? PhoneNumber,
    [property: EmailAddress, MaxLength(320)] string? Email,
    [property: MaxLength(16)] string? Locale,
    [property: MaxLength(64)] string? TimeZone);

public sealed record UpdateProfileRequest(
    [property: Required, MaxLength(120)] string DisplayName,
    [property: MaxLength(16)] string? Locale,
    [property: MaxLength(64)] string? TimeZone,
    [property: Phone, MaxLength(32)] string? PhoneNumber,
    [property: EmailAddress, MaxLength(320)] string? Email);

public sealed record CreateCareInvitationRequest(
    CareContactType ContactType,
    [property: Required, MaxLength(320)] string Contact,
    [property: Required, MaxLength(64)] string ConsentVersion,
    bool ConfirmConsent);

public sealed record AcceptCareInvitationRequest(
    [property: Required, MaxLength(512)] string Token,
    [property: Required, MaxLength(64)] string ConsentVersion,
    bool ConfirmConsent);

public sealed record RejectCareInvitationRequest(
    [property: Required, MaxLength(512)] string Token);

public sealed record CreateMedicationRequest(
    [property: Required, MaxLength(120)] string Name,
    [property: MaxLength(80)] string? StrengthText,
    [property: MaxLength(50)] string? Form,
    [property: MaxLength(500)] string? Notes);

public sealed record UpdateMedicationRequest(
    [property: Range(1, int.MaxValue)] int Version,
    [property: Required, MaxLength(120)] string Name,
    [property: MaxLength(80)] string? StrengthText,
    [property: MaxLength(50)] string? Form,
    [property: MaxLength(500)] string? Notes);

public sealed record TreatmentScheduleRequest(
    DayOfWeek DayOfWeek,
    TimeOnly LocalTime);

public sealed record CreateTreatmentPlanRequest(
    Guid MedicationId,
    [property: Required, MaxLength(80)] string DoseText,
    [property: MaxLength(500)] string? Instructions,
    DateOnly StartDate,
    DateOnly? EndDate,
    [property: Required, MaxLength(64)] string TimeZone,
    IReadOnlyCollection<TreatmentScheduleRequest> Schedules);

public sealed record UpdateTreatmentPlanRequest(
    [property: Range(1, int.MaxValue)] int Version,
    Guid MedicationId,
    [property: Required, MaxLength(80)] string DoseText,
    [property: MaxLength(500)] string? Instructions,
    DateOnly StartDate,
    DateOnly? EndDate,
    [property: Required, MaxLength(64)] string TimeZone,
    IReadOnlyCollection<TreatmentScheduleRequest> Schedules);

public sealed record TreatmentPlanVersionRequest(
    [property: Range(1, int.MaxValue)] int Version);

public sealed record ReportDoseOccurrenceRequest(
    Guid ClientRequestId,
    [property: Range(1, int.MaxValue)] int Version,
    DoseOccurrenceStatus Status,
    DateTime OccurredAtUtc);

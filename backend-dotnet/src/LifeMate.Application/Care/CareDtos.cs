using LifeMate.Domain.Care;

namespace LifeMate.Application.Care;

public sealed record AuthenticatedCareIdentity(
    string AuthSubject,
    string? Email,
    string? PhoneNumber);

public sealed record CreateCareInvitationCommand(
    AuthenticatedCareIdentity Identity,
    CareContactType ContactType,
    string Contact,
    string PatientConsentVersion,
    bool ConfirmedPatientConsent);

public sealed record RespondToCareInvitationCommand(
    AuthenticatedCareIdentity Identity,
    string Token,
    string? CaregiverConsentVersion,
    bool ConfirmedCaregiverConsent,
    bool Accept);

public sealed record CareInvitationCreatedDto(
    Guid Id,
    CareContactType ContactType,
    string ContactHint,
    string Token,
    DateTime ExpiresAtUtc);

public sealed record CareInvitationDto(
    Guid Id,
    CareContactType ContactType,
    string ContactHint,
    string Status,
    DateTime ExpiresAtUtc,
    DateTime CreatedAtUtc);

public sealed record CareRelationshipDto(
    Guid Id,
    Guid PatientUserId,
    string PatientDisplayName,
    Guid CaregiverUserId,
    string CaregiverDisplayName,
    string Status,
    DateTime PatientConsentedAtUtc,
    DateTime CaregiverConsentedAtUtc,
    DateTime? RevokedAtUtc,
    DateTime CreatedAtUtc);

public enum CareErrorKind
{
    Validation,
    NotFound,
    Forbidden,
    Conflict,
    Gone
}

public sealed record CareResult<T>(
    bool Succeeded,
    T? Value,
    CareErrorKind? ErrorKind,
    string? ErrorCode,
    string? ErrorMessage)
{
    public static CareResult<T> Success(T value) => new(true, value, null, null, null);
    public static CareResult<T> Failure(CareErrorKind kind, string code, string message) =>
        new(false, default, kind, code, message);
}

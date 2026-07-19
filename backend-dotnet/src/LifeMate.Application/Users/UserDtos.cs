namespace LifeMate.Application.Users;
public sealed record UserProfileDto(Guid Id, Guid UserId, string DisplayName, string? PhoneNumber, string? Email, string Locale, string TimeZone);
public sealed record AppUserDto(Guid Id, string AuthSubject, string Status, DateTime CreatedAtUtc, DateTime UpdatedAtUtc);
public sealed record CurrentUserDto(AppUserDto User, UserProfileDto Profile);
public sealed record BootstrapUserCommand(string AuthSubject, string? DisplayName, string? PhoneNumber, string? Email, string? Locale, string? TimeZone);
public sealed record UpdateProfileCommand(string AuthSubject, string DisplayName, string? Locale, string? TimeZone, string? PhoneNumber, string? Email);
public sealed record OperationResult<T>(bool Succeeded, T? Value, string? ErrorCode, string? ErrorMessage)
{
    public static OperationResult<T> Success(T value) => new(true, value, null, null);
    public static OperationResult<T> NotFound(string code, string message) => new(false, default, code, message);
    public static OperationResult<T> Validation(string code, string message) => new(false, default, code, message);
}

using LifeMate.Domain.Common;

namespace LifeMate.Domain.Profiles;

public sealed class UserProfile
{
    public const string DefaultLocale = "fa";
    public const string DefaultTimeZone = "Asia/Tehran";

    private UserProfile()
    {
    }

    public UserProfile(
        Guid userId,
        string displayName,
        string? phoneNumber,
        string? email,
        string? locale,
        string? timeZone,
        DateTime utcNow)
    {
        Id = Guid.NewGuid();
        UserId = userId;
        CreatedAtUtc = EnsureUtc(utcNow);
        UpdatedAtUtc = CreatedAtUtc;

        Update(displayName, locale, timeZone, phoneNumber, email, utcNow);
        UpdatedAtUtc = CreatedAtUtc;
    }

    public Guid Id { get; private set; }
    public Guid UserId { get; private set; }
    public string DisplayName { get; private set; } = string.Empty;
    public string? PhoneNumber { get; private set; }
    public string? Email { get; private set; }
    public string Locale { get; private set; } = DefaultLocale;
    public string TimeZone { get; private set; } = DefaultTimeZone;
    public DateTime CreatedAtUtc { get; private set; }
    public DateTime UpdatedAtUtc { get; private set; }

    public void Update(
        string displayName,
        string? locale,
        string? timeZone,
        string? phoneNumber,
        string? email,
        DateTime utcNow)
    {
        if (string.IsNullOrWhiteSpace(displayName) || displayName.Trim().Length > 120)
        {
            throw new DomainException("Display name is required and must be 120 characters or fewer.");
        }

        DisplayName = displayName.Trim();
        Locale = Normalize(locale, DefaultLocale, 16);
        TimeZone = Normalize(timeZone, DefaultTimeZone, 64);
        PhoneNumber = string.IsNullOrWhiteSpace(phoneNumber) ? null : phoneNumber.Trim();
        Email = string.IsNullOrWhiteSpace(email) ? null : email.Trim().ToLowerInvariant();
        UpdatedAtUtc = EnsureUtc(utcNow);
    }

    private static string Normalize(string? value, string fallback, int max)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return fallback;
        }

        var normalized = value.Trim();
        return normalized.Length <= max
            ? normalized
            : throw new DomainException("Value is too long.");
    }

    private static DateTime EnsureUtc(DateTime value) =>
        value.Kind == DateTimeKind.Utc
            ? value
            : throw new DomainException("Timestamps must be UTC.");
}

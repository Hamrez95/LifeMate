using System.ComponentModel.DataAnnotations;
namespace LifeMate.Api.Models;
public sealed record BootstrapUserRequest([property: MaxLength(120)] string? DisplayName, [property: Phone, MaxLength(32)] string? PhoneNumber, [property: EmailAddress, MaxLength(320)] string? Email, [property: MaxLength(16)] string? Locale, [property: MaxLength(64)] string? TimeZone);
public sealed record UpdateProfileRequest([property: Required, MaxLength(120)] string DisplayName, [property: MaxLength(16)] string? Locale, [property: MaxLength(64)] string? TimeZone, [property: Phone, MaxLength(32)] string? PhoneNumber, [property: EmailAddress, MaxLength(320)] string? Email);

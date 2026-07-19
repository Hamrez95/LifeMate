using LifeMate.Domain.Common;

namespace LifeMate.Domain.Users;

public sealed class AppUser
{
    private AppUser() { AuthSubject = string.Empty; }
    public AppUser(string authSubject, DateTime utcNow)
    {
        if (string.IsNullOrWhiteSpace(authSubject)) throw new DomainException("Auth subject is required.");
        Id = Guid.NewGuid(); AuthSubject = authSubject.Trim(); Status = AppUserStatus.Active; CreatedAtUtc = EnsureUtc(utcNow); UpdatedAtUtc = CreatedAtUtc;
    }
    public Guid Id { get; private set; }
    public string AuthSubject { get; private set; }
    public AppUserStatus Status { get; private set; }
    public DateTime CreatedAtUtc { get; private set; }
    public DateTime UpdatedAtUtc { get; private set; }
    public void Suspend(DateTime utcNow) { Status = AppUserStatus.Suspended; UpdatedAtUtc = EnsureUtc(utcNow); }
    public void Delete(DateTime utcNow) { Status = AppUserStatus.Deleted; UpdatedAtUtc = EnsureUtc(utcNow); }
    private static DateTime EnsureUtc(DateTime value) => value.Kind == DateTimeKind.Utc ? value : throw new DomainException("Timestamps must be UTC.");
}

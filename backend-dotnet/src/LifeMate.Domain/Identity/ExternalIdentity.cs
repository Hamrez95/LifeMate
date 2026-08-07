using LifeMate.Domain.Common;

namespace LifeMate.Domain.Identity;

public enum ExternalIdentityStatus
{
    Active,
    Disabled
}

public sealed class ExternalIdentity
{
    private ExternalIdentity()
    {
        Provider = string.Empty;
        Issuer = string.Empty;
        ProviderSubject = string.Empty;
    }

    public ExternalIdentity(
        Guid id,
        Guid accountId,
        string provider,
        string issuer,
        string providerSubject,
        DateTime utcNow)
    {
        if (id == Guid.Empty || accountId == Guid.Empty)
            throw new DomainException("Identity and account ids are required.");
        Provider = Required(provider, 80, "Provider");
        Issuer = Required(issuer, 255, "Issuer");
        ProviderSubject = Required(providerSubject, 512, "Provider subject");
        Id = id;
        AccountId = accountId;
        Status = ExternalIdentityStatus.Active;
        CreatedAtUtc = EnsureUtc(utcNow);
        LastAuthenticatedAtUtc = CreatedAtUtc;
    }

    public Guid Id { get; private set; }
    public Guid AccountId { get; private set; }
    public string Provider { get; private set; }
    public string Issuer { get; private set; }
    public string ProviderSubject { get; private set; }
    public ExternalIdentityStatus Status { get; private set; }
    public DateTime CreatedAtUtc { get; private set; }
    public DateTime LastAuthenticatedAtUtc { get; private set; }

    public void RecordAuthentication(DateTime utcNow)
    {
        var timestamp = EnsureUtc(utcNow);
        if (timestamp < LastAuthenticatedAtUtc)
            throw new DomainException("Authentication time cannot move backwards.");
        LastAuthenticatedAtUtc = timestamp;
        Status = ExternalIdentityStatus.Active;
    }

    public void Disable() => Status = ExternalIdentityStatus.Disabled;

    private static string Required(string value, int max, string name)
    {
        var normalized = value?.Trim() ?? string.Empty;
        if (normalized.Length is 0 || normalized.Length > max)
            throw new DomainException($"{name} is invalid.");
        return normalized;
    }

    private static DateTime EnsureUtc(DateTime value) =>
        value.Kind == DateTimeKind.Utc
            ? value
            : throw new DomainException("Timestamps must be UTC.");
}

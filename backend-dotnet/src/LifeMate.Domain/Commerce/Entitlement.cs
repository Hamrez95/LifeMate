using LifeMate.Domain.Common;

namespace LifeMate.Domain.Commerce;

public enum EntitlementSource
{
    Free,
    Subscription,
    Trial,
    Promotion,
    Gift,
    FamilyPlan,
    Organization,
    Clinic,
    AdminGrant,
    LifetimePurchase
}

public enum EntitlementStatus
{
    Active,
    Revoked,
    Expired
}

/// <summary>
/// Effective commercial capability. It deliberately does not represent
/// authorization or consent to another Person's health data.
/// </summary>
public sealed class Entitlement
{
    private Entitlement()
    {
        FeatureCode = string.Empty;
        SourceKey = string.Empty;
    }

    public Entitlement(
        Guid id,
        string featureCode,
        EntitlementSource source,
        string sourceKey,
        DateTime startsAtUtc,
        Guid? granteeAccountId = null,
        Guid? beneficiaryPersonId = null,
        DateTime? expiresAtUtc = null)
    {
        if (id == Guid.Empty) throw new DomainException("Entitlement id is required.");
        if (granteeAccountId is null && beneficiaryPersonId is null)
            throw new DomainException("Entitlement must have a grantee or beneficiary.");
        if (granteeAccountId == Guid.Empty || beneficiaryPersonId == Guid.Empty)
            throw new DomainException("Entitlement subject ids must not be empty.");

        FeatureCode = Required(featureCode, 160, "Feature code");
        SourceKey = Required(sourceKey, 200, "Entitlement source key");
        StartsAtUtc = EnsureUtc(startsAtUtc);
        ExpiresAtUtc = expiresAtUtc is null ? null : EnsureUtc(expiresAtUtc.Value);
        if (ExpiresAtUtc is not null && ExpiresAtUtc <= StartsAtUtc)
            throw new DomainException("Entitlement expiration must be after its start.");

        Id = id;
        GranteeAccountId = granteeAccountId;
        BeneficiaryPersonId = beneficiaryPersonId;
        Source = source;
        Status = EntitlementStatus.Active;
    }

    public Guid Id { get; private set; }
    public Guid? GranteeAccountId { get; private set; }
    public Guid? BeneficiaryPersonId { get; private set; }
    public string FeatureCode { get; private set; }
    public EntitlementSource Source { get; private set; }
    public string SourceKey { get; private set; }
    public EntitlementStatus Status { get; private set; }
    public DateTime StartsAtUtc { get; private set; }
    public DateTime? ExpiresAtUtc { get; private set; }

    public bool IsActiveAt(DateTime atUtc)
    {
        var now = EnsureUtc(atUtc);
        return Status == EntitlementStatus.Active
            && StartsAtUtc <= now
            && (ExpiresAtUtc is null || ExpiresAtUtc > now);
    }

    public void Revoke() => Status = EntitlementStatus.Revoked;

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

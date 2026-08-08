using LifeMate.Domain.Common;

namespace LifeMate.Domain.Authorization;

public enum AccessGrantStatus
{
    Active,
    Revoked,
    Expired
}

/// <summary>
/// Permission grant to access a Person in a concrete context. Natural or
/// professional relationships are not encoded as permissions here.
/// </summary>
public sealed class AccessGrant
{
    private readonly HashSet<string> _scopes = new(StringComparer.Ordinal);

    private AccessGrant()
    {
        ContextType = string.Empty;
    }

    public AccessGrant(
        Guid id,
        Guid subjectPersonId,
        Guid granteeAccountId,
        string contextType,
        Guid contextId,
        DateTime startsAtUtc,
        DateTime? expiresAtUtc = null)
    {
        if (id == Guid.Empty || subjectPersonId == Guid.Empty || granteeAccountId == Guid.Empty || contextId == Guid.Empty)
            throw new DomainException("Access grant ids are required.");
        ContextType = Required(contextType, 80, "Context type");
        StartsAtUtc = EnsureUtc(startsAtUtc);
        ExpiresAtUtc = expiresAtUtc is null ? null : EnsureUtc(expiresAtUtc.Value);
        if (ExpiresAtUtc is not null && ExpiresAtUtc <= StartsAtUtc)
            throw new DomainException("Access grant expiration must be after its start.");

        Id = id;
        SubjectPersonId = subjectPersonId;
        GranteeAccountId = granteeAccountId;
        ContextId = contextId;
        Status = AccessGrantStatus.Active;
    }

    public Guid Id { get; private set; }
    public Guid SubjectPersonId { get; private set; }
    public Guid GranteeAccountId { get; private set; }
    public string ContextType { get; private set; }
    public Guid ContextId { get; private set; }
    public AccessGrantStatus Status { get; private set; }
    public DateTime StartsAtUtc { get; private set; }
    public DateTime? ExpiresAtUtc { get; private set; }
    public IReadOnlyCollection<string> Scopes => _scopes;

    public void GrantScope(string scope)
    {
        var normalized = Required(scope, 160, "Scope");
        if (!normalized.Contains('.', StringComparison.Ordinal))
            throw new DomainException("Scope must use the documented dotted naming convention.");
        _scopes.Add(normalized);
    }

    public bool HasScope(string scope, DateTime atUtc)
    {
        var now = EnsureUtc(atUtc);
        return Status == AccessGrantStatus.Active
            && StartsAtUtc <= now
            && (ExpiresAtUtc is null || ExpiresAtUtc > now)
            && _scopes.Contains(scope);
    }

    public void Revoke() => Status = AccessGrantStatus.Revoked;

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

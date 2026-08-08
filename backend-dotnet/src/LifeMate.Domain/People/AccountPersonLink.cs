using LifeMate.Domain.Common;

namespace LifeMate.Domain.People;

public enum AccountPersonLinkType
{
    Self,
    Parent,
    Guardian,
    LegalGuardian,
    Proxy
}

public enum AccountPersonLinkStatus
{
    Active,
    Revoked
}

public sealed class AccountPersonLink
{
    private AccountPersonLink() { }

    public AccountPersonLink(
        Guid id,
        Guid accountId,
        Guid personId,
        AccountPersonLinkType linkType,
        DateTime utcNow)
    {
        if (id == Guid.Empty || accountId == Guid.Empty || personId == Guid.Empty)
            throw new DomainException("Account-person link ids are required.");
        Id = id;
        AccountId = accountId;
        PersonId = personId;
        LinkType = linkType;
        Status = AccountPersonLinkStatus.Active;
        CreatedAtUtc = EnsureUtc(utcNow);
    }

    public Guid Id { get; private set; }
    public Guid AccountId { get; private set; }
    public Guid PersonId { get; private set; }
    public AccountPersonLinkType LinkType { get; private set; }
    public AccountPersonLinkStatus Status { get; private set; }
    public DateTime CreatedAtUtc { get; private set; }
    public DateTime? RevokedAtUtc { get; private set; }

    public void Revoke(DateTime utcNow)
    {
        if (Status == AccountPersonLinkStatus.Revoked) return;
        Status = AccountPersonLinkStatus.Revoked;
        RevokedAtUtc = EnsureUtc(utcNow);
    }

    private static DateTime EnsureUtc(DateTime value) =>
        value.Kind == DateTimeKind.Utc
            ? value
            : throw new DomainException("Timestamps must be UTC.");
}

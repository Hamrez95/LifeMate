using LifeMate.Domain.Common;

namespace LifeMate.Domain.Identity;

public enum AccountStatus
{
    Active,
    Suspended,
    DeletionPending,
    Deleted
}

/// <summary>
/// Stable LifeMate login principal. Health ownership belongs to Person, not Account.
/// </summary>
public sealed class Account
{
    private Account() { }

    public Account(Guid id, DateTime utcNow)
    {
        if (id == Guid.Empty) throw new DomainException("Account id is required.");
        Id = id;
        Status = AccountStatus.Active;
        CreatedAtUtc = EnsureUtc(utcNow);
        UpdatedAtUtc = CreatedAtUtc;
    }

    public Guid Id { get; private set; }
    public AccountStatus Status { get; private set; }
    public DateTime CreatedAtUtc { get; private set; }
    public DateTime UpdatedAtUtc { get; private set; }

    public void Suspend(DateTime utcNow)
    {
        if (Status == AccountStatus.Deleted) throw new DomainException("Deleted account cannot be suspended.");
        Status = AccountStatus.Suspended;
        UpdatedAtUtc = EnsureUtc(utcNow);
    }

    public void RequestDeletion(DateTime utcNow)
    {
        if (Status == AccountStatus.Deleted) return;
        Status = AccountStatus.DeletionPending;
        UpdatedAtUtc = EnsureUtc(utcNow);
    }

    public void MarkDeleted(DateTime utcNow)
    {
        Status = AccountStatus.Deleted;
        UpdatedAtUtc = EnsureUtc(utcNow);
    }

    private static DateTime EnsureUtc(DateTime value) =>
        value.Kind == DateTimeKind.Utc
            ? value
            : throw new DomainException("Timestamps must be UTC.");
}

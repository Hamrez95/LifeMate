using LifeMate.Domain.Common;

namespace LifeMate.Domain.Care;

public sealed class CareInvitation
{
    private CareInvitation()
    {
        ContactHash = string.Empty;
        TokenHash = string.Empty;
        PatientConsentVersion = string.Empty;
    }

    public CareInvitation(
        Guid inviterUserId,
        string contactHash,
        string tokenHash,
        string patientConsentVersion,
        DateTime expiresAtUtc,
        DateTime utcNow)
    {
        if (inviterUserId == Guid.Empty) throw new DomainException("Inviter user is required.");
        if (string.IsNullOrWhiteSpace(contactHash)) throw new DomainException("Invitee contact hash is required.");
        if (string.IsNullOrWhiteSpace(tokenHash)) throw new DomainException("Invitation token hash is required.");
        if (string.IsNullOrWhiteSpace(patientConsentVersion) || patientConsentVersion.Length > 64)
            throw new DomainException("A valid patient consent version is required.");

        EnsureUtc(expiresAtUtc);
        EnsureUtc(utcNow);
        if (expiresAtUtc <= utcNow) throw new DomainException("Invitation expiry must be in the future.");

        Id = Guid.NewGuid();
        InviterUserId = inviterUserId;
        ContactHash = contactHash;
        TokenHash = tokenHash;
        PatientConsentVersion = patientConsentVersion.Trim();
        Status = CareInvitationStatus.Pending;
        ExpiresAtUtc = expiresAtUtc;
        CreatedAtUtc = utcNow;
    }

    public Guid Id { get; private set; }
    public Guid InviterUserId { get; private set; }
    public string ContactHash { get; private set; }
    public string TokenHash { get; private set; }
    public string PatientConsentVersion { get; private set; }
    public CareInvitationStatus Status { get; private set; }
    public DateTime ExpiresAtUtc { get; private set; }
    public Guid? RespondedByUserId { get; private set; }
    public DateTime? RespondedAtUtc { get; private set; }
    public DateTime? RevokedAtUtc { get; private set; }
    public DateTime CreatedAtUtc { get; private set; }

    public bool IsExpired(DateTime utcNow) => EnsureUtc(utcNow) >= ExpiresAtUtc;

    public void Accept(Guid inviteeUserId, DateTime utcNow)
    {
        EnsureCanRespond(inviteeUserId, utcNow);
        Status = CareInvitationStatus.Accepted;
        RespondedByUserId = inviteeUserId;
        RespondedAtUtc = utcNow;
    }

    public void Reject(Guid inviteeUserId, DateTime utcNow)
    {
        EnsureCanRespond(inviteeUserId, utcNow);
        Status = CareInvitationStatus.Rejected;
        RespondedByUserId = inviteeUserId;
        RespondedAtUtc = utcNow;
    }

    public bool Revoke(DateTime utcNow)
    {
        EnsureUtc(utcNow);
        if (Status == CareInvitationStatus.Revoked) return false;
        if (Status != CareInvitationStatus.Pending) throw new DomainException("Only a pending invitation can be revoked.");

        Status = CareInvitationStatus.Revoked;
        RevokedAtUtc = utcNow;
        return true;
    }

    public bool Expire(DateTime utcNow)
    {
        EnsureUtc(utcNow);
        if (Status != CareInvitationStatus.Pending || utcNow < ExpiresAtUtc) return false;
        Status = CareInvitationStatus.Expired;
        return true;
    }

    private void EnsureCanRespond(Guid inviteeUserId, DateTime utcNow)
    {
        EnsureUtc(utcNow);
        if (inviteeUserId == Guid.Empty) throw new DomainException("Invitee user is required.");
        if (inviteeUserId == InviterUserId) throw new DomainException("A user cannot accept their own invitation.");
        if (Status != CareInvitationStatus.Pending) throw new DomainException("Invitation is no longer pending.");
        if (utcNow >= ExpiresAtUtc)
        {
            Status = CareInvitationStatus.Expired;
            throw new DomainException("Invitation has expired.");
        }
    }

    private static DateTime EnsureUtc(DateTime value) =>
        value.Kind == DateTimeKind.Utc
            ? value
            : throw new DomainException("Timestamps must be UTC.");
}

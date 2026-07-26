using LifeMate.Domain.Common;

namespace LifeMate.Domain.Care;

public sealed class CareRelationship
{
    private CareRelationship() { }

    public CareRelationship(Guid patientUserId, Guid caregiverUserId, DateTime consentedAtUtc, DateTime utcNow)
    {
        if (patientUserId == Guid.Empty || caregiverUserId == Guid.Empty) throw new DomainException("Both relationship participants are required.");
        if (patientUserId == caregiverUserId) throw new DomainException("A user cannot care for themselves in this relationship.");
        EnsureUtc(consentedAtUtc);
        EnsureUtc(utcNow);

        Id = Guid.NewGuid();
        PatientUserId = patientUserId;
        CaregiverUserId = caregiverUserId;
        Status = CareRelationshipStatus.Active;
        ConsentedAtUtc = consentedAtUtc;
        CreatedAtUtc = utcNow;
        UpdatedAtUtc = utcNow;
    }

    public Guid Id { get; private set; }
    public Guid PatientUserId { get; private set; }
    public Guid CaregiverUserId { get; private set; }
    public CareRelationshipStatus Status { get; private set; }
    public DateTime ConsentedAtUtc { get; private set; }
    public DateTime? RevokedAtUtc { get; private set; }
    public DateTime CreatedAtUtc { get; private set; }
    public DateTime UpdatedAtUtc { get; private set; }

    public void Revoke(DateTime utcNow)
    {
        EnsureUtc(utcNow);
        if (Status == CareRelationshipStatus.Revoked) return;
        Status = CareRelationshipStatus.Revoked;
        RevokedAtUtc = utcNow;
        UpdatedAtUtc = utcNow;
    }

    private static DateTime EnsureUtc(DateTime value) => value.Kind == DateTimeKind.Utc ? value : throw new DomainException("Timestamps must be UTC.");
}

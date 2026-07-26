using LifeMate.Domain.Common;

namespace LifeMate.Domain.Care;

public sealed class CareRelationship
{
    private CareRelationship()
    {
        PatientConsentVersion = string.Empty;
        CaregiverConsentVersion = string.Empty;
    }

    public CareRelationship(
        Guid patientUserId,
        Guid caregiverUserId,
        string patientConsentVersion,
        DateTime patientConsentedAtUtc,
        string caregiverConsentVersion,
        DateTime caregiverConsentedAtUtc,
        DateTime utcNow)
    {
        if (patientUserId == Guid.Empty || caregiverUserId == Guid.Empty)
            throw new DomainException("Both relationship participants are required.");
        if (patientUserId == caregiverUserId)
            throw new DomainException("A user cannot care for themselves in this relationship.");
        if (string.IsNullOrWhiteSpace(patientConsentVersion) || patientConsentVersion.Length > 64)
            throw new DomainException("A valid patient consent version is required.");
        if (string.IsNullOrWhiteSpace(caregiverConsentVersion) || caregiverConsentVersion.Length > 64)
            throw new DomainException("A valid caregiver consent version is required.");

        EnsureUtc(patientConsentedAtUtc);
        EnsureUtc(caregiverConsentedAtUtc);
        EnsureUtc(utcNow);
        if (patientConsentedAtUtc > utcNow || caregiverConsentedAtUtc > utcNow)
            throw new DomainException("Consent timestamps cannot be in the future.");

        Id = Guid.NewGuid();
        PatientUserId = patientUserId;
        CaregiverUserId = caregiverUserId;
        PatientConsentVersion = patientConsentVersion.Trim();
        PatientConsentedAtUtc = patientConsentedAtUtc;
        CaregiverConsentVersion = caregiverConsentVersion.Trim();
        CaregiverConsentedAtUtc = caregiverConsentedAtUtc;
        Status = CareRelationshipStatus.Active;
        CreatedAtUtc = utcNow;
        UpdatedAtUtc = utcNow;
    }

    public Guid Id { get; private set; }
    public Guid PatientUserId { get; private set; }
    public Guid CaregiverUserId { get; private set; }
    public CareRelationshipStatus Status { get; private set; }
    public string PatientConsentVersion { get; private set; }
    public DateTime PatientConsentedAtUtc { get; private set; }
    public string CaregiverConsentVersion { get; private set; }
    public DateTime CaregiverConsentedAtUtc { get; private set; }
    public Guid? RevokedByUserId { get; private set; }
    public DateTime? RevokedAtUtc { get; private set; }
    public DateTime CreatedAtUtc { get; private set; }
    public DateTime UpdatedAtUtc { get; private set; }

    public bool Revoke(Guid actorUserId, DateTime utcNow)
    {
        EnsureUtc(utcNow);
        if (actorUserId != PatientUserId && actorUserId != CaregiverUserId)
            throw new DomainException("Only a relationship participant can revoke access.");
        if (Status == CareRelationshipStatus.Revoked) return false;

        Status = CareRelationshipStatus.Revoked;
        RevokedByUserId = actorUserId;
        RevokedAtUtc = utcNow;
        UpdatedAtUtc = utcNow;
        return true;
    }

    private static DateTime EnsureUtc(DateTime value) =>
        value.Kind == DateTimeKind.Utc
            ? value
            : throw new DomainException("Timestamps must be UTC.");
}

namespace LifeMate.Domain.Consents;
public enum PrivacyDocumentType { Terms = 1, Privacy = 2 }
public sealed class PrivacyConsent
{
    private PrivacyConsent() { DocumentVersion = string.Empty; }
    public Guid Id { get; private set; } = Guid.NewGuid();
    public Guid UserId { get; private set; }
    public PrivacyDocumentType DocumentType { get; private set; }
    public string DocumentVersion { get; private set; }
    public DateTime GrantedAtUtc { get; private set; }
    public DateTime? RevokedAtUtc { get; private set; }
    public DateTime CreatedAtUtc { get; private set; }
}

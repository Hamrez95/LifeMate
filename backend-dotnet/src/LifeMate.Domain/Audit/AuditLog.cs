namespace LifeMate.Domain.Audit;
public sealed class AuditLog
{
    private AuditLog() { Action = string.Empty; ResourceType = string.Empty; }
    public AuditLog(Guid? actorUserId, string action, string resourceType, Guid? resourceId, string? metadataJson, DateTime utcNow)
    { Id = Guid.NewGuid(); ActorUserId = actorUserId; Action = action; ResourceType = resourceType; ResourceId = resourceId; MetadataJson = metadataJson; CreatedAtUtc = utcNow; }
    public Guid Id { get; private set; }
    public Guid? ActorUserId { get; private set; }
    public string Action { get; private set; }
    public string ResourceType { get; private set; }
    public Guid? ResourceId { get; private set; }
    public string? MetadataJson { get; private set; }
    public DateTime CreatedAtUtc { get; private set; }
}

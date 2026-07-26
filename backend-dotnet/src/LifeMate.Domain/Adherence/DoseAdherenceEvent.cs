using LifeMate.Domain.Common;

namespace LifeMate.Domain.Adherence;

public sealed class DoseAdherenceEvent
{
    private DoseAdherenceEvent() { }

    public DoseAdherenceEvent(
        Guid occurrenceId,
        Guid actorUserId,
        Guid clientRequestId,
        DoseAdherenceEventType eventType,
        DoseOccurrenceStatus previousStatus,
        DoseOccurrenceStatus resultingStatus,
        DateTime occurredAtUtc,
        DateTime recordedAtUtc)
    {
        if (occurrenceId == Guid.Empty) throw new DomainException("Dose occurrence is required.");
        if (actorUserId == Guid.Empty) throw new DomainException("Adherence event actor is required.");
        if (clientRequestId == Guid.Empty) throw new DomainException("Client request id is required.");
        EnsureUtc(occurredAtUtc);
        EnsureUtc(recordedAtUtc);

        Id = Guid.NewGuid();
        OccurrenceId = occurrenceId;
        ActorUserId = actorUserId;
        ClientRequestId = clientRequestId;
        EventType = eventType;
        PreviousStatus = previousStatus;
        ResultingStatus = resultingStatus;
        OccurredAtUtc = occurredAtUtc;
        RecordedAtUtc = recordedAtUtc;
    }

    public Guid Id { get; private set; }
    public Guid OccurrenceId { get; private set; }
    public Guid ActorUserId { get; private set; }
    public Guid ClientRequestId { get; private set; }
    public DoseAdherenceEventType EventType { get; private set; }
    public DoseOccurrenceStatus PreviousStatus { get; private set; }
    public DoseOccurrenceStatus ResultingStatus { get; private set; }
    public DateTime OccurredAtUtc { get; private set; }
    public DateTime RecordedAtUtc { get; private set; }

    private static DateTime EnsureUtc(DateTime value) =>
        value.Kind == DateTimeKind.Utc
            ? value
            : throw new DomainException("Timestamps must be UTC.");
}

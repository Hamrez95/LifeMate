using LifeMate.Domain.Adherence;
using LifeMate.Domain.Common;
using Xunit;

namespace LifeMate.UnitTests;

public sealed class AdherenceDomainTests
{
    [Fact]
    public void Patient_report_records_initial_action_and_correction()
    {
        var now = DateTime.UtcNow;
        var occurrence = CreateOccurrence(now);

        var first = occurrence.ApplyPatientReport(
            DoseOccurrenceStatus.Taken,
            now.AddMinutes(1),
            now.AddMinutes(1));

        Assert.Equal(DoseAdherenceEventType.Taken, first);
        Assert.Equal(DoseOccurrenceStatus.Taken, occurrence.Status);
        Assert.Equal(2, occurrence.Version);

        var duplicate = occurrence.ApplyPatientReport(
            DoseOccurrenceStatus.Taken,
            now.AddMinutes(2),
            now.AddMinutes(2));
        Assert.Null(duplicate);
        Assert.Equal(2, occurrence.Version);

        var correction = occurrence.ApplyPatientReport(
            DoseOccurrenceStatus.Skipped,
            now.AddMinutes(3),
            now.AddMinutes(3));
        Assert.Equal(DoseAdherenceEventType.Corrected, correction);
        Assert.Equal(DoseOccurrenceStatus.Skipped, occurrence.Status);
        Assert.Equal(3, occurrence.Version);
    }

    [Fact]
    public void Missed_occurrence_can_later_be_reported_taken()
    {
        var now = DateTime.UtcNow;
        var occurrence = CreateOccurrence(now);
        Assert.True(occurrence.MarkMissed(now.AddHours(1)));

        var report = occurrence.ApplyPatientReport(
            DoseOccurrenceStatus.Taken,
            now.AddHours(2),
            now.AddHours(2));

        Assert.Equal(DoseAdherenceEventType.Corrected, report);
        Assert.Equal(DoseOccurrenceStatus.Taken, occurrence.Status);
    }

    [Fact]
    public void Reported_occurrence_cannot_be_cancelled()
    {
        var now = DateTime.UtcNow;
        var occurrence = CreateOccurrence(now);
        occurrence.ApplyPatientReport(DoseOccurrenceStatus.Taken, now, now);

        Assert.Throws<DomainException>(() => occurrence.Cancel(now.AddMinutes(1)));
    }

    [Fact]
    public void Cancelled_occurrence_cannot_be_reported()
    {
        var now = DateTime.UtcNow;
        var occurrence = CreateOccurrence(now);
        Assert.True(occurrence.Cancel(now.AddMinutes(1)));

        Assert.Throws<DomainException>(() => occurrence.ApplyPatientReport(
            DoseOccurrenceStatus.Taken,
            now.AddMinutes(2),
            now.AddMinutes(2)));
    }

    [Fact]
    public void Adherence_event_requires_client_idempotency_key()
    {
        Assert.Throws<DomainException>(() => new DoseAdherenceEvent(
            Guid.NewGuid(),
            Guid.NewGuid(),
            Guid.Empty,
            DoseAdherenceEventType.Taken,
            DoseOccurrenceStatus.Scheduled,
            DoseOccurrenceStatus.Taken,
            DateTime.UtcNow,
            DateTime.UtcNow));
    }

    private static DoseOccurrence CreateOccurrence(DateTime now) => new(
        Guid.NewGuid(),
        Guid.NewGuid(),
        Guid.NewGuid(),
        now,
        new DateOnly(2026, 8, 1),
        new TimeOnly(8, 30),
        "Asia/Tehran",
        now);
}

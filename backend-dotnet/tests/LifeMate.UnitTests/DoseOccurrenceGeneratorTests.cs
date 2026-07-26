using LifeMate.Application.Adherence;
using LifeMate.Domain.Common;
using LifeMate.Domain.Treatments;
using Xunit;

namespace LifeMate.UnitTests;

public sealed class DoseOccurrenceGeneratorTests
{
    [Fact]
    public void Generate_is_deterministic_and_respects_plan_dates()
    {
        var now = DateTime.UtcNow;
        var plan = new TreatmentPlan(
            Guid.NewGuid(),
            Guid.NewGuid(),
            "one tablet",
            null,
            new DateOnly(2026, 8, 3),
            new DateOnly(2026, 8, 10),
            "Asia/Tehran",
            now);
        var monday = new TreatmentSchedule(plan.Id, DayOfWeek.Monday, new TimeOnly(8, 0), now);
        var thursday = new TreatmentSchedule(plan.Id, DayOfWeek.Thursday, new TimeOnly(20, 30), now);

        var first = DoseOccurrenceGenerator.Generate(
            plan,
            [monday, thursday],
            new DateOnly(2026, 8, 1),
            new DateOnly(2026, 8, 15));
        var second = DoseOccurrenceGenerator.Generate(
            plan,
            [monday, thursday],
            new DateOnly(2026, 8, 1),
            new DateOnly(2026, 8, 15));

        Assert.Equal(3, first.Occurrences.Count);
        Assert.Equal(first.Occurrences, second.Occurrences);
        Assert.All(first.Occurrences, x =>
        {
            Assert.InRange(x.LocalDate, plan.StartDate, plan.EndDate!.Value);
            Assert.Equal(DateTimeKind.Utc, x.ScheduledAtUtc.Kind);
        });
    }

    [Fact]
    public void Generate_rejects_ranges_longer_than_31_days()
    {
        var now = DateTime.UtcNow;
        var plan = CreatePlan("Asia/Tehran", now);

        Assert.Throws<DomainException>(() => DoseOccurrenceGenerator.Generate(
            plan,
            [],
            new DateOnly(2026, 1, 1),
            new DateOnly(2026, 2, 1)));
    }

    [Fact]
    public void Generate_returns_no_occurrences_for_paused_plan()
    {
        var now = DateTime.UtcNow;
        var plan = CreatePlan("Asia/Tehran", now);
        plan.Pause(now.AddMinutes(1));
        var schedule = new TreatmentSchedule(plan.Id, DayOfWeek.Monday, new TimeOnly(8, 0), now);

        var result = DoseOccurrenceGenerator.Generate(
            plan,
            [schedule],
            new DateOnly(2026, 8, 1),
            new DateOnly(2026, 8, 7));

        Assert.Empty(result.Occurrences);
    }

    [Fact]
    public void Generate_skips_spring_forward_gap_instead_of_inventing_an_instant()
    {
        const string zone = "America/New_York";
        if (!CanLoad(zone)) return;

        var now = DateTime.UtcNow;
        var plan = new TreatmentPlan(
            Guid.NewGuid(),
            Guid.NewGuid(),
            "one tablet",
            null,
            new DateOnly(2026, 3, 8),
            new DateOnly(2026, 3, 8),
            zone,
            now);
        var schedule = new TreatmentSchedule(plan.Id, DayOfWeek.Sunday, new TimeOnly(2, 30), now);

        var result = DoseOccurrenceGenerator.Generate(
            plan,
            [schedule],
            new DateOnly(2026, 3, 8),
            new DateOnly(2026, 3, 8));

        Assert.Empty(result.Occurrences);
        Assert.Equal(1, result.SkippedInvalidLocalTimes);
    }

    [Fact]
    public void Generate_chooses_one_stable_instant_for_fall_back_ambiguity()
    {
        const string zone = "America/New_York";
        if (!CanLoad(zone)) return;

        var now = DateTime.UtcNow;
        var plan = new TreatmentPlan(
            Guid.NewGuid(),
            Guid.NewGuid(),
            "one tablet",
            null,
            new DateOnly(2026, 11, 1),
            new DateOnly(2026, 11, 1),
            zone,
            now);
        var schedule = new TreatmentSchedule(plan.Id, DayOfWeek.Sunday, new TimeOnly(1, 30), now);

        var first = DoseOccurrenceGenerator.Generate(
            plan,
            [schedule],
            plan.StartDate,
            plan.StartDate);
        var second = DoseOccurrenceGenerator.Generate(
            plan,
            [schedule],
            plan.StartDate,
            plan.StartDate);

        var occurrence = Assert.Single(first.Occurrences);
        Assert.Equal(occurrence, Assert.Single(second.Occurrences));
        Assert.Equal(new DateTime(2026, 11, 1, 5, 30, 0, DateTimeKind.Utc), occurrence.ScheduledAtUtc);
    }

    private static TreatmentPlan CreatePlan(string zone, DateTime now) => new(
        Guid.NewGuid(),
        Guid.NewGuid(),
        "one tablet",
        null,
        new DateOnly(2026, 1, 1),
        null,
        zone,
        now);

    private static bool CanLoad(string id)
    {
        try
        {
            _ = TimeZoneInfo.FindSystemTimeZoneById(id);
            return true;
        }
        catch (TimeZoneNotFoundException)
        {
            return false;
        }
        catch (InvalidTimeZoneException)
        {
            return false;
        }
    }
}

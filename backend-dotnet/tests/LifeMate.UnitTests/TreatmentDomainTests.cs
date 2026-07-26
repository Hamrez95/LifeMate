using LifeMate.Domain.Common;
using LifeMate.Domain.Treatments;
using Xunit;

namespace LifeMate.UnitTests;

public sealed class TreatmentDomainTests
{
    [Fact]
    public void Medication_normalizes_optional_fields_and_tracks_version()
    {
        var now = DateTime.UtcNow;
        var medication = new Medication(
            Guid.NewGuid(),
            "  Atorvastatin  ",
            " 20 mg ",
            " tablet ",
            " after dinner ",
            now);

        Assert.Equal("Atorvastatin", medication.Name);
        Assert.Equal("20 mg", medication.StrengthText);
        Assert.Equal(1, medication.Version);

        medication.Update("Atorvastatin", "40 mg", "tablet", null, now.AddMinutes(1));

        Assert.Equal("40 mg", medication.StrengthText);
        Assert.Null(medication.Notes);
        Assert.Equal(2, medication.Version);
    }

    [Fact]
    public void Medication_requires_utc_timestamp_and_valid_name()
    {
        Assert.Throws<DomainException>(() => new Medication(
            Guid.NewGuid(),
            " ",
            null,
            null,
            null,
            DateTime.UtcNow));

        Assert.Throws<DomainException>(() => new Medication(
            Guid.NewGuid(),
            "Medicine",
            null,
            null,
            null,
            DateTime.Now));
    }

    [Fact]
    public void Treatment_plan_rejects_invalid_date_range()
    {
        var now = DateTime.UtcNow;

        Assert.Throws<DomainException>(() => new TreatmentPlan(
            Guid.NewGuid(),
            Guid.NewGuid(),
            "one tablet",
            null,
            new DateOnly(2026, 8, 10),
            new DateOnly(2026, 8, 9),
            "Asia/Tehran",
            now));
    }

    [Fact]
    public void Treatment_plan_lifecycle_is_idempotent_and_archival_is_terminal()
    {
        var now = DateTime.UtcNow;
        var plan = CreatePlan(now);

        Assert.True(plan.Pause(now.AddMinutes(1)));
        Assert.False(plan.Pause(now.AddMinutes(2)));
        Assert.True(plan.Resume(now.AddMinutes(3)));
        Assert.False(plan.Resume(now.AddMinutes(4)));
        Assert.True(plan.Archive(now.AddMinutes(5)));
        Assert.False(plan.Archive(now.AddMinutes(6)));
        Assert.Equal(TreatmentPlanStatus.Archived, plan.Status);
        Assert.Equal(4, plan.Version);

        Assert.Throws<DomainException>(() => plan.Resume(now.AddMinutes(7)));
        Assert.Throws<DomainException>(() => plan.Update(
            Guid.NewGuid(),
            "one tablet",
            null,
            new DateOnly(2026, 8, 1),
            null,
            "Asia/Tehran",
            now.AddMinutes(8)));
    }

    [Fact]
    public void Treatment_schedule_uses_explicit_day_and_minute_precision()
    {
        var schedule = new TreatmentSchedule(
            Guid.NewGuid(),
            DayOfWeek.Saturday,
            new TimeOnly(8, 30, 45),
            DateTime.UtcNow);

        Assert.Equal(DayOfWeek.Saturday, schedule.DayOfWeek);
        Assert.Equal(new TimeOnly(8, 30), schedule.LocalTime);
    }

    [Fact]
    public void Treatment_schedule_rejects_unknown_day_value()
    {
        Assert.Throws<DomainException>(() => new TreatmentSchedule(
            Guid.NewGuid(),
            (DayOfWeek)99,
            new TimeOnly(8, 30),
            DateTime.UtcNow));
    }

    private static TreatmentPlan CreatePlan(DateTime now) => new(
        Guid.NewGuid(),
        Guid.NewGuid(),
        "one tablet",
        "after dinner",
        new DateOnly(2026, 8, 1),
        null,
        "Asia/Tehran",
        now);
}

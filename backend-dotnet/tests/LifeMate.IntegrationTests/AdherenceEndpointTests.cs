using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Serialization;
using LifeMate.Api.Models;
using LifeMate.Application.Adherence;
using LifeMate.Application.Treatments;
using LifeMate.Domain.Adherence;
using LifeMate.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Xunit;

namespace LifeMate.IntegrationTests;

public sealed class AdherenceEndpointTests : IClassFixture<LifeMateApiFactory>
{
    private static readonly JsonSerializerOptions JsonOptions = CreateJsonOptions();
    private readonly LifeMateApiFactory _factory;

    public AdherenceEndpointTests(LifeMateApiFactory factory) => _factory = factory;

    [Fact]
    public async Task Dose_generation_reporting_and_retries_are_patient_owned_and_idempotent()
    {
        var patient = await CreateBootstrappedClientAsync(
            "adherence-patient",
            "adherence-patient@example.test",
            "Adherence Patient");
        var unrelated = await CreateBootstrappedClientAsync(
            "adherence-unrelated",
            "adherence-unrelated@example.test",
            "Adherence Unrelated");

        var medicationResponse = await patient.PostAsJsonAsync(
            "/api/v1/medications",
            new CreateMedicationRequest("Atorvastatin", "20 mg", "tablet", null),
            JsonOptions);
        var medication = await medicationResponse.Content.ReadFromJsonAsync<MedicationDto>(JsonOptions);
        Assert.NotNull(medication);

        var planResponse = await patient.PostAsJsonAsync(
            "/api/v1/treatment-plans",
            new CreateTreatmentPlanRequest(
                medication.Id,
                "one tablet",
                "after dinner",
                new DateOnly(2026, 8, 1),
                new DateOnly(2026, 8, 7),
                "Asia/Tehran",
                [
                    new TreatmentScheduleRequest(DayOfWeek.Saturday, new TimeOnly(8, 30)),
                    new TreatmentScheduleRequest(DayOfWeek.Sunday, new TimeOnly(20, 0))
                ]),
            JsonOptions);
        planResponse.EnsureSuccessStatusCode();
        var plan = await planResponse.Content.ReadFromJsonAsync<TreatmentPlanDto>(JsonOptions);
        Assert.NotNull(plan);

        const string range = "?fromDate=2026-08-01&toDate=2026-08-07";
        var first = await patient.GetFromJsonAsync<List<DoseOccurrenceDto>>(
            "/api/v1/dose-occurrences" + range,
            JsonOptions);
        Assert.NotNull(first);
        Assert.Equal(2, first.Count);
        Assert.All(first, x => Assert.Equal("scheduled", x.Status));

        var second = await patient.GetFromJsonAsync<List<DoseOccurrenceDto>>(
            "/api/v1/dose-occurrences" + range,
            JsonOptions);
        Assert.Equal(first.Select(x => x.Id), second!.Select(x => x.Id));

        var pause = await patient.PostAsJsonAsync(
            $"/api/v1/treatment-plans/{plan.Id}/pause",
            new TreatmentPlanVersionRequest(plan.Version),
            JsonOptions);
        pause.EnsureSuccessStatusCode();
        var paused = await pause.Content.ReadFromJsonAsync<TreatmentPlanDto>(JsonOptions);
        var hiddenWhilePaused = await patient.GetFromJsonAsync<List<DoseOccurrenceDto>>(
            "/api/v1/dose-occurrences" + range,
            JsonOptions);
        Assert.Empty(hiddenWhilePaused!);

        var resume = await patient.PostAsJsonAsync(
            $"/api/v1/treatment-plans/{plan.Id}/resume",
            new TreatmentPlanVersionRequest(paused!.Version),
            JsonOptions);
        resume.EnsureSuccessStatusCode();
        var visibleAfterResume = await patient.GetFromJsonAsync<List<DoseOccurrenceDto>>(
            "/api/v1/dose-occurrences" + range,
            JsonOptions);
        Assert.Equal(first.Select(x => x.Id), visibleAfterResume!.Select(x => x.Id));

        var unrelatedDoses = await unrelated.GetFromJsonAsync<List<DoseOccurrenceDto>>(
            "/api/v1/dose-occurrences" + range,
            JsonOptions);
        Assert.Empty(unrelatedDoses!);

        var dose = first[0];
        var requestId = Guid.NewGuid();
        var reportRequest = new ReportDoseOccurrenceRequest(
            requestId,
            dose.Version,
            DoseOccurrenceStatus.Taken,
            DateTime.UtcNow);
        var report = await patient.PostAsJsonAsync(
            $"/api/v1/dose-occurrences/{dose.Id}/report",
            reportRequest,
            JsonOptions);
        report.EnsureSuccessStatusCode();
        var reported = await report.Content.ReadFromJsonAsync<DoseOccurrenceDto>(JsonOptions);
        Assert.Equal("taken", reported!.Status);
        Assert.Equal(dose.Version + 1, reported.Version);

        var replay = await patient.PostAsJsonAsync(
            $"/api/v1/dose-occurrences/{dose.Id}/report",
            reportRequest,
            JsonOptions);
        replay.EnsureSuccessStatusCode();
        var replayed = await replay.Content.ReadFromJsonAsync<DoseOccurrenceDto>(JsonOptions);
        Assert.Equal(reported.Version, replayed!.Version);

        var reusedKey = await patient.PostAsJsonAsync(
            $"/api/v1/dose-occurrences/{dose.Id}/report",
            reportRequest with { Status = DoseOccurrenceStatus.Skipped },
            JsonOptions);
        Assert.Equal(HttpStatusCode.Conflict, reusedKey.StatusCode);

        var unrelatedReport = await unrelated.PostAsJsonAsync(
            $"/api/v1/dose-occurrences/{dose.Id}/report",
            reportRequest with { ClientRequestId = Guid.NewGuid() },
            JsonOptions);
        Assert.Equal(HttpStatusCode.NotFound, unrelatedReport.StatusCode);

        using var scope = _factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<LifeMateDbContext>();
        Assert.Equal(2, await db.DoseOccurrences.CountAsync());
        Assert.Single(await db.DoseAdherenceEvents.ToListAsync());
        Assert.True(await db.AuditLogs.AnyAsync(x =>
            x.Action == "dose.reported" && x.ResourceId == dose.Id));
    }

    [Fact]
    public async Task Oversized_or_reversed_ranges_are_rejected()
    {
        var patient = await CreateBootstrappedClientAsync(
            "adherence-range-patient",
            "adherence-range@example.test",
            "Adherence Range");

        var reversed = await patient.GetAsync(
            "/api/v1/dose-occurrences?fromDate=2026-08-02&toDate=2026-08-01");
        Assert.Equal(HttpStatusCode.BadRequest, reversed.StatusCode);

        var oversized = await patient.GetAsync(
            "/api/v1/dose-occurrences?fromDate=2026-08-01&toDate=2026-09-01");
        Assert.Equal(HttpStatusCode.BadRequest, oversized.StatusCode);
    }

    private async Task<HttpClient> CreateBootstrappedClientAsync(
        string subject,
        string email,
        string displayName)
    {
        var client = _factory.CreateClient();
        client.DefaultRequestHeaders.Authorization = new(TestAuthHandler.SchemeName, subject);
        client.DefaultRequestHeaders.Add(TestAuthHandler.EmailHeader, email);
        var bootstrap = await client.PostAsJsonAsync(
            "/api/v1/users/bootstrap",
            new BootstrapUserRequest(displayName, null, email, "fa", "Asia/Tehran"));
        bootstrap.EnsureSuccessStatusCode();
        return client;
    }

    private static JsonSerializerOptions CreateJsonOptions()
    {
        var options = new JsonSerializerOptions(JsonSerializerDefaults.Web);
        options.Converters.Add(new JsonStringEnumConverter(JsonNamingPolicy.CamelCase, allowIntegerValues: false));
        return options;
    }
}

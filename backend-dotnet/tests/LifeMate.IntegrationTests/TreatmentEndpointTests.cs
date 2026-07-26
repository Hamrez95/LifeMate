using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Serialization;
using LifeMate.Api.Models;
using LifeMate.Application.Treatments;
using LifeMate.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Xunit;

namespace LifeMate.IntegrationTests;

public sealed class TreatmentEndpointTests : IClassFixture<LifeMateApiFactory>
{
    private static readonly JsonSerializerOptions JsonOptions = CreateJsonOptions();
    private readonly LifeMateApiFactory _factory;

    public TreatmentEndpointTests(LifeMateApiFactory factory) => _factory = factory;

    [Fact]
    public async Task Treatment_data_is_patient_owned_versioned_and_lifecycle_controlled()
    {
        var patient = await CreateBootstrappedClientAsync(
            "treatment-patient-a",
            "treatment-patient-a@example.test",
            "Treatment Patient A");
        var unrelated = await CreateBootstrappedClientAsync(
            "treatment-unrelated-a",
            "treatment-unrelated-a@example.test",
            "Treatment Unrelated A");

        var medicationResponse = await patient.PostAsJsonAsync(
            "/api/v1/medications",
            new CreateMedicationRequest("Atorvastatin", "20 mg", "tablet", "after dinner"),
            JsonOptions);
        Assert.Equal(HttpStatusCode.Created, medicationResponse.StatusCode);
        var medication = await medicationResponse.Content.ReadFromJsonAsync<MedicationDto>(JsonOptions);
        Assert.NotNull(medication);
        Assert.Equal(1, medication.Version);

        var unrelatedMedicationUpdate = await unrelated.PutAsJsonAsync(
            $"/api/v1/medications/{medication.Id}",
            new UpdateMedicationRequest(1, "Changed", null, null, null),
            JsonOptions);
        Assert.Equal(HttpStatusCode.NotFound, unrelatedMedicationUpdate.StatusCode);

        var unrelatedPlan = await unrelated.PostAsJsonAsync(
            "/api/v1/treatment-plans",
            CreatePlanRequest(medication.Id),
            JsonOptions);
        Assert.Equal(HttpStatusCode.BadRequest, unrelatedPlan.StatusCode);

        var planResponse = await patient.PostAsJsonAsync(
            "/api/v1/treatment-plans",
            CreatePlanRequest(medication.Id),
            JsonOptions);
        Assert.Equal(HttpStatusCode.Created, planResponse.StatusCode);
        var plan = await planResponse.Content.ReadFromJsonAsync<TreatmentPlanDto>(JsonOptions);
        Assert.NotNull(plan);
        Assert.Equal("active", plan.Status);
        Assert.Equal(1, plan.Version);
        Assert.Equal(2, plan.Schedules.Count);

        var unrelatedPlans = await unrelated.GetFromJsonAsync<List<TreatmentPlanDto>>(
            "/api/v1/treatment-plans",
            JsonOptions);
        Assert.Empty(unrelatedPlans!);

        var updatedResponse = await patient.PutAsJsonAsync(
            $"/api/v1/treatment-plans/{plan.Id}",
            new UpdateTreatmentPlanRequest(
                plan.Version,
                medication.Id,
                "one tablet",
                "after breakfast",
                new DateOnly(2026, 8, 1),
                null,
                "Asia/Tehran",
                [new TreatmentScheduleRequest(DayOfWeek.Monday, new TimeOnly(7, 45))]),
            JsonOptions);
        updatedResponse.EnsureSuccessStatusCode();
        var updated = await updatedResponse.Content.ReadFromJsonAsync<TreatmentPlanDto>(JsonOptions);
        Assert.NotNull(updated);
        Assert.Equal(2, updated.Version);
        Assert.Single(updated.Schedules);
        Assert.Equal(DayOfWeek.Monday, updated.Schedules.Single().DayOfWeek);

        var staleUpdate = await patient.PutAsJsonAsync(
            $"/api/v1/treatment-plans/{plan.Id}",
            new UpdateTreatmentPlanRequest(
                1,
                medication.Id,
                "two tablets",
                null,
                new DateOnly(2026, 8, 1),
                null,
                "Asia/Tehran",
                [new TreatmentScheduleRequest(DayOfWeek.Monday, new TimeOnly(7, 45))]),
            JsonOptions);
        Assert.Equal(HttpStatusCode.Conflict, staleUpdate.StatusCode);

        var pause = await patient.PostAsJsonAsync(
            $"/api/v1/treatment-plans/{plan.Id}/pause",
            new TreatmentPlanVersionRequest(updated.Version),
            JsonOptions);
        pause.EnsureSuccessStatusCode();
        var paused = await pause.Content.ReadFromJsonAsync<TreatmentPlanDto>(JsonOptions);
        Assert.Equal("paused", paused!.Status);

        var archive = await patient.PostAsJsonAsync(
            $"/api/v1/treatment-plans/{plan.Id}/archive",
            new TreatmentPlanVersionRequest(paused.Version),
            JsonOptions);
        archive.EnsureSuccessStatusCode();
        var archived = await archive.Content.ReadFromJsonAsync<TreatmentPlanDto>(JsonOptions);
        Assert.Equal("archived", archived!.Status);

        var resumeArchived = await patient.PostAsJsonAsync(
            $"/api/v1/treatment-plans/{plan.Id}/resume",
            new TreatmentPlanVersionRequest(archived.Version),
            JsonOptions);
        Assert.Equal(HttpStatusCode.BadRequest, resumeArchived.StatusCode);

        var visibleByDefault = await patient.GetFromJsonAsync<List<TreatmentPlanDto>>(
            "/api/v1/treatment-plans",
            JsonOptions);
        Assert.Empty(visibleByDefault!);
        var visibleWithArchive = await patient.GetFromJsonAsync<List<TreatmentPlanDto>>(
            "/api/v1/treatment-plans?includeArchived=true",
            JsonOptions);
        Assert.Contains(visibleWithArchive!, x => x.Id == plan.Id);

        using var scope = _factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<LifeMateDbContext>();
        Assert.True(await db.AuditLogs.AnyAsync(x =>
            x.Action == "medication.created" && x.ResourceId == medication.Id));
        Assert.True(await db.AuditLogs.AnyAsync(x =>
            x.Action == "treatment_plan.created" && x.ResourceId == plan.Id));
        Assert.True(await db.AuditLogs.AnyAsync(x =>
            x.Action == "treatment_plan.updated" && x.ResourceId == plan.Id));
        Assert.True(await db.AuditLogs.AnyAsync(x =>
            x.Action == "treatment_plan.archived" && x.ResourceId == plan.Id));
        var storedSchedules = await db.TreatmentSchedules
            .Where(x => x.TreatmentPlanId == plan.Id)
            .ToListAsync();
        Assert.Single(storedSchedules);
    }

    [Fact]
    public async Task Invalid_timezone_and_duplicate_schedule_are_rejected_without_partial_data()
    {
        var patient = await CreateBootstrappedClientAsync(
            "treatment-patient-validation",
            "treatment-validation@example.test",
            "Treatment Validation");
        var medicationResponse = await patient.PostAsJsonAsync(
            "/api/v1/medications",
            new CreateMedicationRequest("Medication", null, null, null),
            JsonOptions);
        var medication = await medicationResponse.Content.ReadFromJsonAsync<MedicationDto>(JsonOptions);

        var invalidTimezone = await patient.PostAsJsonAsync(
            "/api/v1/treatment-plans",
            CreatePlanRequest(medication!.Id) with { TimeZone = "Iran Standard Time" },
            JsonOptions);
        Assert.Equal(HttpStatusCode.BadRequest, invalidTimezone.StatusCode);

        var duplicateSchedule = await patient.PostAsJsonAsync(
            "/api/v1/treatment-plans",
            CreatePlanRequest(medication.Id) with
            {
                Schedules =
                [
                    new TreatmentScheduleRequest(DayOfWeek.Saturday, new TimeOnly(8, 30, 1)),
                    new TreatmentScheduleRequest(DayOfWeek.Saturday, new TimeOnly(8, 30, 59))
                ]
            },
            JsonOptions);
        Assert.Equal(HttpStatusCode.BadRequest, duplicateSchedule.StatusCode);

        var plans = await patient.GetFromJsonAsync<List<TreatmentPlanDto>>(
            "/api/v1/treatment-plans?includeArchived=true",
            JsonOptions);
        Assert.Empty(plans!);
    }

    private static CreateTreatmentPlanRequest CreatePlanRequest(Guid medicationId) => new(
        medicationId,
        "one tablet",
        "after dinner",
        new DateOnly(2026, 8, 1),
        null,
        "Asia/Tehran",
        [
            new TreatmentScheduleRequest(DayOfWeek.Saturday, new TimeOnly(8, 30)),
            new TreatmentScheduleRequest(DayOfWeek.Sunday, new TimeOnly(20, 0))
        ]);

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

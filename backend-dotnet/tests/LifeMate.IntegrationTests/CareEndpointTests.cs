using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Serialization;
using LifeMate.Api.Models;
using LifeMate.Application.Abstractions;
using LifeMate.Application.Care;
using LifeMate.Domain.Care;
using LifeMate.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Xunit;

namespace LifeMate.IntegrationTests;

public sealed class CareEndpointTests : IClassFixture<LifeMateApiFactory>
{
    private const string PatientConsentVersion = CareConsentPolicy.PatientVersion;
    private const string CaregiverConsentVersion = CareConsentPolicy.CaregiverVersion;
    private static readonly JsonSerializerOptions JsonOptions = CreateJsonOptions();
    private readonly LifeMateApiFactory _factory;

    public CareEndpointTests(LifeMateApiFactory factory) => _factory = factory;

    [Fact]
    public async Task Invitation_acceptance_is_contact_bound_audited_and_visible_only_to_participants()
    {
        var patient = await CreateBootstrappedClientAsync(
            "care-patient-a",
            "patient-a@example.test",
            "Patient A");
        var caregiver = await CreateBootstrappedClientAsync(
            "care-caregiver-a",
            "caregiver-a@example.test",
            "Caregiver A");
        var unrelated = await CreateBootstrappedClientAsync(
            "care-unrelated-a",
            "unrelated-a@example.test",
            "Unrelated A");

        var create = await patient.PostAsJsonAsync(
            "/api/v1/care/invitations",
            new CreateCareInvitationRequest(
                CareContactType.Email,
                "Caregiver-A@Example.Test",
                PatientConsentVersion,
                true));

        Assert.Equal(HttpStatusCode.Created, create.StatusCode);
        var invitation = await create.Content.ReadFromJsonAsync<CareInvitationCreatedDto>(JsonOptions);
        Assert.NotNull(invitation);
        Assert.False(string.IsNullOrWhiteSpace(invitation.Token));
        Assert.DoesNotContain("caregiver-a@example.test", invitation.ContactHint, StringComparison.OrdinalIgnoreCase);

        var wrongIdentity = await unrelated.PostAsJsonAsync(
            "/api/v1/care/invitations/accept",
            new AcceptCareInvitationRequest(invitation.Token, CaregiverConsentVersion, true));
        Assert.Equal(HttpStatusCode.Forbidden, wrongIdentity.StatusCode);

        var accept = await caregiver.PostAsJsonAsync(
            "/api/v1/care/invitations/accept",
            new AcceptCareInvitationRequest(invitation.Token, CaregiverConsentVersion, true));
        accept.EnsureSuccessStatusCode();
        var relationship = await accept.Content.ReadFromJsonAsync<CareRelationshipDto>(JsonOptions);
        Assert.NotNull(relationship);
        Assert.Equal("active", relationship.Status);

        var patientRelationships = await patient.GetFromJsonAsync<List<CareRelationshipDto>>(
            "/api/v1/care/relationships");
        var caregiverRelationships = await caregiver.GetFromJsonAsync<List<CareRelationshipDto>>(
            "/api/v1/care/relationships");
        var unrelatedRelationships = await unrelated.GetFromJsonAsync<List<CareRelationshipDto>>(
            "/api/v1/care/relationships");

        Assert.Contains(patientRelationships!, x => x.Id == relationship.Id);
        Assert.Contains(caregiverRelationships!, x => x.Id == relationship.Id);
        Assert.DoesNotContain(unrelatedRelationships!, x => x.Id == relationship.Id);

        var unrelatedRevoke = await unrelated.DeleteAsync(
            $"/api/v1/care/relationships/{relationship.Id}");
        Assert.Equal(HttpStatusCode.NotFound, unrelatedRevoke.StatusCode);

        var revoke = await patient.DeleteAsync(
            $"/api/v1/care/relationships/{relationship.Id}");
        revoke.EnsureSuccessStatusCode();
        var revoked = await revoke.Content.ReadFromJsonAsync<CareRelationshipDto>(JsonOptions);
        Assert.Equal("revoked", revoked!.Status);

        using var scope = _factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<LifeMateDbContext>();
        var storedInvitation = await db.CareInvitations.SingleAsync(x => x.Id == invitation.Id);
        var secretService = scope.ServiceProvider.GetRequiredService<IInvitationSecretService>();

        Assert.Equal(secretService.HashToken(invitation.Token), storedInvitation.TokenHash);
        Assert.NotEqual(invitation.Token, storedInvitation.TokenHash);
        Assert.DoesNotContain("caregiver-a@example.test", storedInvitation.ContactHint, StringComparison.OrdinalIgnoreCase);
        Assert.Equal(PatientConsentVersion, storedInvitation.PatientConsentVersion);
        Assert.False(await db.AuditLogs.AnyAsync(x =>
            x.MetadataJson != null && x.MetadataJson.Contains(invitation.Token)));
        Assert.True(await db.AuditLogs.AnyAsync(x =>
            x.Action == "care_invitation.created" && x.ResourceId == invitation.Id));
        Assert.True(await db.AuditLogs.AnyAsync(x =>
            x.Action == "care_relationship.created" && x.ResourceId == relationship.Id));
        Assert.True(await db.AuditLogs.AnyAsync(x =>
            x.Action == "care_relationship.revoked" && x.ResourceId == relationship.Id));
    }

    [Fact]
    public async Task Pending_duplicate_is_blocked_but_rejection_allows_a_new_invitation()
    {
        var patient = await CreateBootstrappedClientAsync(
            "care-patient-duplicate",
            "patient-duplicate@example.test",
            "Patient Duplicate");
        var caregiver = await CreateBootstrappedClientAsync(
            "care-caregiver-duplicate",
            "caregiver-duplicate@example.test",
            "Caregiver Duplicate");

        var request = new CreateCareInvitationRequest(
            CareContactType.Email,
            "caregiver-duplicate@example.test",
            PatientConsentVersion,
            true);

        var first = await patient.PostAsJsonAsync("/api/v1/care/invitations", request);
        first.EnsureSuccessStatusCode();
        var invitation = await first.Content.ReadFromJsonAsync<CareInvitationCreatedDto>(JsonOptions);

        var duplicate = await patient.PostAsJsonAsync("/api/v1/care/invitations", request);
        Assert.Equal(HttpStatusCode.Conflict, duplicate.StatusCode);

        var reject = await caregiver.PostAsJsonAsync(
            "/api/v1/care/invitations/reject",
            new RejectCareInvitationRequest(invitation!.Token));
        reject.EnsureSuccessStatusCode();
        var rejected = await reject.Content.ReadFromJsonAsync<CareInvitationDto>(JsonOptions);
        Assert.Equal("rejected", rejected!.Status);

        var replacement = await patient.PostAsJsonAsync("/api/v1/care/invitations", request);
        Assert.Equal(HttpStatusCode.Created, replacement.StatusCode);

        using var scope = _factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<LifeMateDbContext>();
        var patientUserId = (await db.Users.SingleAsync(
            user => user.AuthSubject == "care-patient-duplicate")).Id;
        Assert.False(await db.CareRelationships.AnyAsync(
            relationship => relationship.PatientUserId == patientUserId));
        Assert.True(await db.AuditLogs.AnyAsync(x =>
            x.Action == "care_invitation.rejected" && x.ResourceId == invitation.Id));
    }

    [Fact]
    public async Task Expired_invitation_returns_gone_and_cannot_create_relationship()
    {
        var patient = await CreateBootstrappedClientAsync(
            "care-patient-expired",
            "patient-expired@example.test",
            "Patient Expired");
        var caregiver = await CreateBootstrappedClientAsync(
            "care-caregiver-expired",
            "caregiver-expired@example.test",
            "Caregiver Expired");

        var create = await patient.PostAsJsonAsync(
            "/api/v1/care/invitations",
            new CreateCareInvitationRequest(
                CareContactType.Email,
                "caregiver-expired@example.test",
                PatientConsentVersion,
                true));
        create.EnsureSuccessStatusCode();
        var invitation = await create.Content.ReadFromJsonAsync<CareInvitationCreatedDto>(JsonOptions);

        using (var scope = _factory.Services.CreateScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<LifeMateDbContext>();
            await db.Database.ExecuteSqlInterpolatedAsync(
                $"UPDATE lifemate.care_invitations SET expires_at_utc = {DateTime.UtcNow.AddMinutes(-1)} WHERE id = {invitation!.Id}");
        }

        var accept = await caregiver.PostAsJsonAsync(
            "/api/v1/care/invitations/accept",
            new AcceptCareInvitationRequest(invitation!.Token, CaregiverConsentVersion, true));
        Assert.Equal(HttpStatusCode.Gone, accept.StatusCode);

        using var verificationScope = _factory.Services.CreateScope();
        var verificationDb = verificationScope.ServiceProvider.GetRequiredService<LifeMateDbContext>();
        Assert.False(await verificationDb.CareRelationships.AnyAsync());
        Assert.Equal(
            CareInvitationStatus.Expired,
            (await verificationDb.CareInvitations.SingleAsync(x => x.Id == invitation.Id)).Status);
    }

    [Fact]
    public async Task Explicit_and_current_patient_and_caregiver_consent_are_required()
    {
        var patient = await CreateBootstrappedClientAsync(
            "care-patient-consent",
            "patient-consent@example.test",
            "Patient Consent");
        var caregiver = await CreateBootstrappedClientAsync(
            "care-caregiver-consent",
            "caregiver-consent@example.test",
            "Caregiver Consent");

        var missingPatientConsent = await patient.PostAsJsonAsync(
            "/api/v1/care/invitations",
            new CreateCareInvitationRequest(
                CareContactType.Email,
                "caregiver-consent@example.test",
                PatientConsentVersion,
                false));
        Assert.Equal(HttpStatusCode.BadRequest, missingPatientConsent.StatusCode);

        var stalePatientConsent = await patient.PostAsJsonAsync(
            "/api/v1/care/invitations",
            new CreateCareInvitationRequest(
                CareContactType.Email,
                "caregiver-consent@example.test",
                "care-patient-consent-v0",
                true));
        Assert.Equal(HttpStatusCode.BadRequest, stalePatientConsent.StatusCode);

        var create = await patient.PostAsJsonAsync(
            "/api/v1/care/invitations",
            new CreateCareInvitationRequest(
                CareContactType.Email,
                "caregiver-consent@example.test",
                PatientConsentVersion,
                true));
        create.EnsureSuccessStatusCode();
        var invitation = await create.Content.ReadFromJsonAsync<CareInvitationCreatedDto>(JsonOptions);

        var missingCaregiverConsent = await caregiver.PostAsJsonAsync(
            "/api/v1/care/invitations/accept",
            new AcceptCareInvitationRequest(invitation!.Token, CaregiverConsentVersion, false));
        Assert.Equal(HttpStatusCode.BadRequest, missingCaregiverConsent.StatusCode);

        var staleCaregiverConsent = await caregiver.PostAsJsonAsync(
            "/api/v1/care/invitations/accept",
            new AcceptCareInvitationRequest(invitation.Token, "care-caregiver-consent-v0", true));
        Assert.Equal(HttpStatusCode.BadRequest, staleCaregiverConsent.StatusCode);
    }

    [Fact]
    public async Task Self_invitation_using_authenticated_contact_is_rejected()
    {
        var patient = await CreateBootstrappedClientAsync(
            "care-self-invite",
            "self-invite@example.test",
            "Self Invite");

        var response = await patient.PostAsJsonAsync(
            "/api/v1/care/invitations",
            new CreateCareInvitationRequest(
                CareContactType.Email,
                "SELF-INVITE@example.test",
                PatientConsentVersion,
                true));

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    private static JsonSerializerOptions CreateJsonOptions()
    {
        var options = new JsonSerializerOptions(JsonSerializerDefaults.Web);
        options.Converters.Add(new JsonStringEnumConverter(JsonNamingPolicy.CamelCase));
        return options;
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
}

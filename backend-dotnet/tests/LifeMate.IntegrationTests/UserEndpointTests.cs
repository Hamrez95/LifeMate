using System.Net;
using System.Net.Http.Json;
using LifeMate.Api.Models;
using LifeMate.Application.Users;
using LifeMate.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Xunit;

namespace LifeMate.IntegrationTests;

public sealed class UserEndpointTests : IClassFixture<LifeMateApiFactory>
{
    private readonly LifeMateApiFactory _factory;
    public UserEndpointTests(LifeMateApiFactory factory) => _factory = factory;

    [Fact]
    public async Task Anonymous_me_returns_401()
    {
        var res = await _factory.CreateClient().GetAsync("/api/v1/me");
        Assert.Equal(HttpStatusCode.Unauthorized, res.StatusCode);
    }

    [Fact]
    public async Task Health_live_works_without_authentication()
    {
        var res = await _factory.CreateClient().GetAsync("/health/live");
        Assert.True(res.IsSuccessStatusCode);
    }

    [Fact]
    public async Task Health_ready_reports_database_connectivity()
    {
        var res = await _factory.CreateClient().GetAsync("/health/ready");
        Assert.Equal(HttpStatusCode.OK, res.StatusCode);
    }

    [Fact]
    public async Task Valid_identity_can_bootstrap_and_repeated_bootstrap_does_not_duplicate_and_audits_bootstrap()
    {
        var client = _factory.CreateClient();
        client.DefaultRequestHeaders.Authorization = new("Test", "subject-a");

        var first = await client.PostAsJsonAsync("/api/v1/users/bootstrap", new BootstrapUserRequest("User A", null, "a@example.test", "fa", "Asia/Tehran"));
        first.EnsureSuccessStatusCode();
        var second = await client.PostAsJsonAsync("/api/v1/users/bootstrap", new BootstrapUserRequest("Different", null, null, null, null));
        second.EnsureSuccessStatusCode();

        using var scope = _factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<LifeMateDbContext>();
        Assert.Equal(1, await db.Users.CountAsync(x => x.AuthSubject == "subject-a"));
        var userA = await db.Users.SingleAsync(x => x.AuthSubject == "subject-a");
        Assert.Equal(1, await db.UserProfiles.CountAsync(x => x.UserId == userA.Id));
        Assert.Equal(1, await db.AuditLogs.CountAsync(x => x.Action == "user.bootstrap" && x.ActorUserId == userA.Id));
    }

    [Fact]
    public async Task Test_identity_cannot_access_another_users_resource()
    {
        var clientA = _factory.CreateClient();
        clientA.DefaultRequestHeaders.Authorization = new("Test", "subject-isolation-a");
        var bootstrapA = await clientA.PostAsJsonAsync("/api/v1/users/bootstrap", new BootstrapUserRequest("User A", null, null, null, null));
        bootstrapA.EnsureSuccessStatusCode();

        var clientB = _factory.CreateClient();
        clientB.DefaultRequestHeaders.Authorization = new("Test", "subject-isolation-b");
        var bootstrapB = await clientB.PostAsJsonAsync("/api/v1/users/bootstrap", new BootstrapUserRequest("User B", null, null, null, null));
        bootstrapB.EnsureSuccessStatusCode();

        var meB = await clientB.GetFromJsonAsync<CurrentUserDto>("/api/v1/me?userId=ignored");
        Assert.NotNull(meB);
        Assert.Equal("subject-isolation-b", meB.User.AuthSubject);
        Assert.NotEqual("subject-isolation-a", meB.User.AuthSubject);
    }

    [Fact]
    public async Task Invalid_profile_payload_returns_validation_errors()
    {
        var client = _factory.CreateClient();
        client.DefaultRequestHeaders.Authorization = new("Test", "subject-c");
        await client.PostAsJsonAsync("/api/v1/users/bootstrap", new BootstrapUserRequest("User C", null, null, null, null));

        var res = await client.PutAsJsonAsync("/api/v1/me/profile", new UpdateProfileRequest("", "fa", "Asia/Tehran", null, "not-email"));

        Assert.Equal(HttpStatusCode.BadRequest, res.StatusCode);
    }

    [Fact]
    public async Task Profile_update_creates_audit_record()
    {
        var client = _factory.CreateClient();
        client.DefaultRequestHeaders.Authorization = new("Test", "subject-profile-audit");
        var bootstrap = await client.PostAsJsonAsync("/api/v1/users/bootstrap", new BootstrapUserRequest("Audit User", null, null, null, null));
        bootstrap.EnsureSuccessStatusCode();

        var update = await client.PutAsJsonAsync("/api/v1/me/profile", new UpdateProfileRequest("Audit User Updated", "fa", "Asia/Tehran", null, null));
        update.EnsureSuccessStatusCode();

        using var scope = _factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<LifeMateDbContext>();
        var user = await db.Users.SingleAsync(x => x.AuthSubject == "subject-profile-audit");
        Assert.Equal(1, await db.AuditLogs.CountAsync(x => x.Action == "user_profile.update" && x.ActorUserId == user.Id));
    }
}

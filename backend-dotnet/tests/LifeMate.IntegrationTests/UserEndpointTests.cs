using System.Net;
using System.Net.Http.Json;
using LifeMate.Api.Models;
using LifeMate.Infrastructure.Persistence;
using Microsoft.Extensions.DependencyInjection;
using Xunit;

namespace LifeMate.IntegrationTests;

public sealed class UserEndpointTests : IClassFixture<LifeMateApiFactory>
{
    private readonly LifeMateApiFactory _factory;
    public UserEndpointTests(LifeMateApiFactory factory) => _factory = factory;
    [Fact] public async Task Anonymous_me_returns_401() { var res = await _factory.CreateClient().GetAsync("/api/v1/me"); Assert.Equal(HttpStatusCode.Unauthorized, res.StatusCode); }
    [Fact] public async Task Health_live_works_without_authentication() { var res = await _factory.CreateClient().GetAsync("/health/live"); Assert.True(res.IsSuccessStatusCode); }
    [Fact] public async Task Health_ready_reports_database_state() { var res = await _factory.CreateClient().GetAsync("/health/ready"); Assert.True(res.StatusCode is HttpStatusCode.OK or HttpStatusCode.ServiceUnavailable); }
    [Fact] public async Task Valid_identity_can_bootstrap_and_repeated_bootstrap_does_not_duplicate()
    {
        var client = _factory.CreateClient(); client.DefaultRequestHeaders.Authorization = new("Test", "subject-a");
        var first = await client.PostAsJsonAsync("/api/v1/users/bootstrap", new BootstrapUserRequest("User A", null, "a@example.test", "fa", "Asia/Tehran")); first.EnsureSuccessStatusCode();
        var second = await client.PostAsJsonAsync("/api/v1/users/bootstrap", new BootstrapUserRequest("Different", null, null, null, null)); second.EnsureSuccessStatusCode();
        using var scope = _factory.Services.CreateScope(); Assert.Equal(1, scope.ServiceProvider.GetRequiredService<LifeMateDbContext>().Users.Count());
    }
    [Fact] public async Task Users_cannot_select_another_profile() { var client = _factory.CreateClient(); client.DefaultRequestHeaders.Authorization = new("Test", "subject-b"); await client.PostAsJsonAsync("/api/v1/users/bootstrap", new BootstrapUserRequest("User B", null, null, null, null)); var me = await client.GetAsync("/api/v1/me?userId=00000000-0000-0000-0000-000000000000"); Assert.True(me.IsSuccessStatusCode); }
    [Fact] public async Task Invalid_profile_payload_returns_validation_errors() { var client = _factory.CreateClient(); client.DefaultRequestHeaders.Authorization = new("Test", "subject-c"); await client.PostAsJsonAsync("/api/v1/users/bootstrap", new BootstrapUserRequest("User C", null, null, null, null)); var res = await client.PutAsJsonAsync("/api/v1/me/profile", new UpdateProfileRequest("", "fa", "Asia/Tehran", null, "not-email")); Assert.Equal(HttpStatusCode.BadRequest, res.StatusCode); }
}

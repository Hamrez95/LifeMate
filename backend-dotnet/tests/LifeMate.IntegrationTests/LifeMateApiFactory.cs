using LifeMate.Infrastructure.Persistence;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Testcontainers.PostgreSql;

namespace LifeMate.IntegrationTests;

public sealed class LifeMateApiFactory : WebApplicationFactory<Program>, IAsyncLifetime
{
    private readonly PostgreSqlContainer _postgres = new PostgreSqlBuilder().WithImage("postgres:17-alpine").WithDatabase("lifemate_tests").WithUsername("lifemate").WithPassword("lifemate_test_password").Build();
    public async Task InitializeAsync() { await _postgres.StartAsync(); using var scope = Services.CreateScope(); await scope.ServiceProvider.GetRequiredService<LifeMateDbContext>().Database.MigrateAsync(); }
    public new async Task DisposeAsync() => await _postgres.DisposeAsync();
    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.UseEnvironment("Development");
        builder.ConfigureServices(services =>
        {
            var descriptor = services.SingleOrDefault(d => d.ServiceType == typeof(DbContextOptions<LifeMateDbContext>)); if (descriptor is not null) services.Remove(descriptor);
            services.AddDbContext<LifeMateDbContext>(options => options.UseNpgsql(_postgres.GetConnectionString()));
            services.AddAuthentication(options => { options.DefaultAuthenticateScheme = TestAuthHandler.Scheme; options.DefaultChallengeScheme = TestAuthHandler.Scheme; }).AddScheme<AuthenticationSchemeOptions, TestAuthHandler>(TestAuthHandler.Scheme, _ => { });
        });
    }
}

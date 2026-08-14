using LifeMate.Infrastructure.Persistence;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Npgsql;
using Xunit;

namespace LifeMate.IntegrationTests;

public sealed class LifeMateApiFactory : WebApplicationFactory<Program>, IAsyncLifetime
{
    private readonly string _databaseName;
    private readonly string _connectionString;
    private readonly string _adminConnectionString;

    public LifeMateApiFactory()
    {
        var baseConnectionString =
            Environment.GetEnvironmentVariable("LIFEMATE_INTEGRATION_DB_CONNECTION")
            ?? Environment.GetEnvironmentVariable("ConnectionStrings__LifeMateDb")
            ?? throw new InvalidOperationException(
                "Integration tests require LIFEMATE_INTEGRATION_DB_CONNECTION or ConnectionStrings__LifeMateDb.");

        _databaseName = $"lifemate_test_{Guid.NewGuid():N}";

        var applicationBuilder = new NpgsqlConnectionStringBuilder(baseConnectionString)
        {
            Database = _databaseName,
            Pooling = false
        };
        _connectionString = applicationBuilder.ConnectionString;

        var adminBuilder = new NpgsqlConnectionStringBuilder(baseConnectionString)
        {
            Database = "postgres",
            Pooling = false
        };
        _adminConnectionString = adminBuilder.ConnectionString;
    }

    public async Task InitializeAsync()
    {
        await using (var adminConnection = new NpgsqlConnection(_adminConnectionString))
        {
            await adminConnection.OpenAsync();
            await using var createDatabase = adminConnection.CreateCommand();
            createDatabase.CommandText = $"CREATE DATABASE \"{_databaseName}\"";
            await createDatabase.ExecuteNonQueryAsync();
        }

        using var scope = Services.CreateScope();
        var dbContext = scope.ServiceProvider.GetRequiredService<LifeMateDbContext>();
        await dbContext.Database.MigrateAsync();
    }

    public new async Task DisposeAsync()
    {
        await base.DisposeAsync();
        NpgsqlConnection.ClearAllPools();

        await using var adminConnection = new NpgsqlConnection(_adminConnectionString);
        await adminConnection.OpenAsync();
        await using var dropDatabase = adminConnection.CreateCommand();
        dropDatabase.CommandText = $"DROP DATABASE IF EXISTS \"{_databaseName}\" WITH (FORCE)";
        await dropDatabase.ExecuteNonQueryAsync();
    }

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.UseEnvironment("Testing");
        builder.ConfigureAppConfiguration((_, configuration) =>
        {
            configuration.AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["ConnectionStrings:LifeMateDb"] = _connectionString,
                ["Security:Invitations:ContactPepper"] =
                    "integration-test-contact-pepper-at-least-32-bytes"
            });
        });

        builder.ConfigureServices(services =>
        {
            var descriptor = services.SingleOrDefault(
                service => service.ServiceType == typeof(DbContextOptions<LifeMateDbContext>));

            if (descriptor is not null)
            {
                services.Remove(descriptor);
            }

            services.AddDbContext<LifeMateDbContext>(options =>
                options.UseNpgsql(
                    _connectionString,
                    npgsql => npgsql.MigrationsHistoryTable(
                        "__ef_migrations_history",
                        "lifemate")));

            services
                .AddAuthentication(options =>
                {
                    options.DefaultAuthenticateScheme = TestAuthHandler.SchemeName;
                    options.DefaultChallengeScheme = TestAuthHandler.SchemeName;
                })
                .AddScheme<AuthenticationSchemeOptions, TestAuthHandler>(
                    TestAuthHandler.SchemeName,
                    _ => { });
        });
    }
}

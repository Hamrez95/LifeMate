using LifeMate.Application.Abstractions;
using LifeMate.Application.Users;
using LifeMate.Infrastructure.Persistence;
using LifeMate.Infrastructure.Time;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;

namespace LifeMate.Infrastructure;

public static class DependencyInjection
{
    public static IServiceCollection AddLifeMateInfrastructure(this IServiceCollection services, IConfiguration configuration)
    {
        var connectionString = configuration.GetConnectionString("LifeMateDb")
            ?? configuration["LIFEMATE_DB_CONNECTION"]
            ?? throw new InvalidOperationException("Database connection is not configured.");

        services.AddDbContext<LifeMateDbContext>(options =>
            options.UseNpgsql(
                connectionString,
                npgsql => npgsql.MigrationsHistoryTable("__ef_migrations_history", "lifemate")));

        services.AddScoped<IAppDbContext>(sp => sp.GetRequiredService<LifeMateDbContext>());
        services.AddSingleton<IClock, SystemClock>();
        services.AddScoped<UserService>();

        return services;
    }
}

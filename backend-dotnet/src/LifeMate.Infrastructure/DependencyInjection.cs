using System.Text;
using LifeMate.Application.Abstractions;
using LifeMate.Application.Adherence;
using LifeMate.Application.Care;
using LifeMate.Application.Treatments;
using LifeMate.Application.Users;
using LifeMate.Infrastructure.Persistence;
using LifeMate.Infrastructure.Security;
using LifeMate.Infrastructure.Time;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;

namespace LifeMate.Infrastructure;

public static class DependencyInjection
{
    public static IServiceCollection AddLifeMateInfrastructure(
        this IServiceCollection services,
        IConfiguration configuration)
    {
        var connectionString = configuration.GetConnectionString("LifeMateDb")
            ?? configuration["LIFEMATE_DB_CONNECTION"]
            ?? throw new InvalidOperationException("Database connection is not configured.");

        services.AddDbContext<LifeMateDbContext>(options =>
            options.UseNpgsql(
                connectionString,
                npgsql => npgsql.MigrationsHistoryTable("__ef_migrations_history", "lifemate")));

        services.AddOptions<InvitationSecretOptions>()
            .Bind(configuration.GetSection(InvitationSecretOptions.SectionName))
            .Validate(
                options => !string.IsNullOrWhiteSpace(options.ContactPepper)
                    && Encoding.UTF8.GetByteCount(options.ContactPepper) >= 32,
                "Invitation contact pepper must contain at least 32 UTF-8 bytes.")
            .ValidateOnStart();

        services.AddScoped<IAppDbContext>(sp => sp.GetRequiredService<LifeMateDbContext>());
        services.AddSingleton<IClock, SystemClock>();
        services.AddSingleton<ITimeZoneValidator, SystemTimeZoneValidator>();
        services.AddSingleton<IInvitationSecretService, InvitationSecretService>();
        services.AddScoped<UserService>();
        services.AddScoped<CareService>();
        services.AddScoped<TreatmentService>();
        services.AddScoped<AdherenceService>();

        return services;
    }
}

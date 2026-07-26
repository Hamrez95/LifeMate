using System.Text.Json;
using System.Text.Json.Serialization;
using System.Threading.RateLimiting;
using LifeMate.Api.Endpoints;
using LifeMate.Api.Middleware;
using LifeMate.Api.Security;
using LifeMate.Infrastructure;
using LifeMate.Infrastructure.Persistence;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Diagnostics.HealthChecks;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.JsonWebTokens;
using Microsoft.IdentityModel.Tokens;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddProblemDetails();
builder.Services.AddOpenApi();
builder.Services.ConfigureHttpJsonOptions(options =>
    options.SerializerOptions.Converters.Add(
        new JsonStringEnumConverter(JsonNamingPolicy.CamelCase, allowIntegerValues: false)));
builder.Services.AddHealthChecks().AddDbContextCheck<LifeMateDbContext>("postgresql");
builder.Services.AddLifeMateInfrastructure(builder.Configuration);

var allowedOrigins = builder.Configuration.GetSection("Cors:AllowedOrigins").Get<string[]>() ?? [];
builder.Services.AddCors(options =>
    options.AddPolicy("restricted", policy =>
    {
        if (allowedOrigins.Length > 0)
        {
            policy.WithOrigins(allowedOrigins).AllowAnyHeader().AllowAnyMethod();
        }
    }));

builder.Services.Configure<SupabaseJwtOptions>(builder.Configuration.GetSection("Authentication:Supabase"));
builder.Services
    .AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(options =>
    {
        var config = builder.Configuration
            .GetSection("Authentication:Supabase")
            .Get<SupabaseJwtOptions>() ?? new SupabaseJwtOptions();

        if (string.IsNullOrWhiteSpace(config.Issuer))
        {
            throw new InvalidOperationException("Authentication:Supabase:Issuer is required.");
        }

        options.RequireHttpsMetadata = config.RequireHttpsMetadata;
        options.MapInboundClaims = false;
        options.TokenValidationParameters = new TokenValidationParameters
        {
            ValidateIssuerSigningKey = true,
            ValidateIssuer = true,
            ValidIssuer = config.Issuer,
            ValidateAudience = true,
            ValidAudience = config.Audience,
            ValidateLifetime = true,
            ClockSkew = TimeSpan.FromMinutes(2),
            NameClaimType = JwtRegisteredClaimNames.Sub
        };

        if (!string.IsNullOrWhiteSpace(config.MetadataAddress))
        {
            options.MetadataAddress = config.MetadataAddress;
        }
        else if (!string.IsNullOrWhiteSpace(config.JwksUri))
        {
            options.ConfigurationManager = new JwksConfigurationManager(config.JwksUri);
        }
    });

builder.Services.AddAuthorization();
builder.Services.AddRateLimiter(options =>
{
    options.RejectionStatusCode = StatusCodes.Status429TooManyRequests;
    options.AddPolicy(
        "api-write",
        context => RateLimitPartition.GetFixedWindowLimiter(
            context.User.FindFirst("sub")?.Value
                ?? context.Connection.RemoteIpAddress?.ToString()
                ?? "anonymous",
            _ => new FixedWindowRateLimiterOptions
            {
                PermitLimit = 20,
                Window = TimeSpan.FromMinutes(1),
                QueueLimit = 0
            }));
});

var app = builder.Build();

if (!app.Environment.IsEnvironment("Testing"))
{
    app.UseExceptionHandler();
}

app.UseMiddleware<CorrelationIdMiddleware>();
app.UseCors("restricted");

if (app.Environment.IsDevelopment() || builder.Configuration.GetValue("OpenApi:Enabled", false))
{
    app.MapOpenApi().AllowAnonymous();
}

app.UseAuthentication();
app.UseRateLimiter();
app.UseAuthorization();
app.MapHealthChecks("/health/live", new HealthCheckOptions { Predicate = _ => false }).AllowAnonymous();
app.MapHealthChecks("/health/ready").AllowAnonymous();
app.MapUserEndpoints();
app.MapCareEndpoints();
app.MapTreatmentEndpoints();
app.Run();

public partial class Program
{
}

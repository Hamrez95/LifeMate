using System.Diagnostics;
using System.Text.RegularExpressions;

namespace LifeMate.Api.Middleware;

public sealed partial class CorrelationIdMiddleware
{
    public const string HeaderName = "X-Correlation-ID";
    private readonly RequestDelegate _next;

    public CorrelationIdMiddleware(RequestDelegate next) => _next = next;

    public async Task InvokeAsync(HttpContext context)
    {
        var correlationId = NormalizeCorrelationId(
            context.Request.Headers[HeaderName].FirstOrDefault());
        context.TraceIdentifier = correlationId;
        context.Response.Headers[HeaderName] = correlationId;

        using var activity = Activity.Current is null
            ? new Activity("LifeMate.Request").Start()
            : null;
        Activity.Current?.SetTag("lifemate.correlation_id", correlationId);

        await _next(context);
    }

    public static string NormalizeCorrelationId(string? candidate)
    {
        if (!string.IsNullOrWhiteSpace(candidate))
        {
            var value = candidate.Trim();
            if (SafeCorrelationId().IsMatch(value))
            {
                return value;
            }
        }

        return Guid.NewGuid().ToString("N");
    }

    [GeneratedRegex(
        "^(?:[0-9A-Fa-f]{32}|[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12})$",
        RegexOptions.CultureInvariant)]
    private static partial Regex SafeCorrelationId();
}

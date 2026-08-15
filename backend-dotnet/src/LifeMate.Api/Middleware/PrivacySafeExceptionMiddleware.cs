using System.Diagnostics;

namespace LifeMate.Api.Middleware;

public sealed class PrivacySafeExceptionMiddleware
{
    private readonly RequestDelegate _next;
    private readonly ILogger<PrivacySafeExceptionMiddleware> _logger;

    public PrivacySafeExceptionMiddleware(
        RequestDelegate next,
        ILogger<PrivacySafeExceptionMiddleware> logger)
    {
        _next = next;
        _logger = logger;
    }

    public async Task InvokeAsync(HttpContext context)
    {
        try
        {
            await _next(context);
        }
        catch (Exception exception)
        {
            var correlationId = context.TraceIdentifier;
            if (string.IsNullOrWhiteSpace(correlationId))
            {
                correlationId = Activity.Current?.TraceId.ToString()
                    ?? Guid.NewGuid().ToString("N");
            }

            // Deliberately do not pass the Exception instance or message to the
            // logger. Exception messages may contain request, identity, or
            // health context. Type + correlation ID are enough to group and
            // investigate the failure through privacy-safe traces.
            _logger.LogError(
                "Unhandled LifeMate API failure. CorrelationId={CorrelationId} ExceptionType={ExceptionType}",
                correlationId,
                exception.GetType().Name);

            if (context.Response.HasStarted)
            {
                context.Abort();
                return;
            }

            context.Response.Clear();
            context.Response.StatusCode = StatusCodes.Status500InternalServerError;
            context.Response.ContentType = "application/problem+json";
            context.Response.Headers[CorrelationIdMiddleware.HeaderName] = correlationId;
            await context.Response.WriteAsJsonAsync(new
            {
                type = "about:blank",
                title = "internal_error",
                status = StatusCodes.Status500InternalServerError,
                detail = "The request could not be completed.",
                correlationId
            });
        }
    }
}

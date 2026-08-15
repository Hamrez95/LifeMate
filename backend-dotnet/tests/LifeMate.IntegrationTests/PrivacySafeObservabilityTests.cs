using System.Text.RegularExpressions;
using LifeMate.Api.Middleware;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Logging.Abstractions;

namespace LifeMate.IntegrationTests;

public sealed class PrivacySafeObservabilityTests
{
    [Fact]
    public void CorrelationId_RejectsFreeFormSensitiveInput()
    {
        const string sensitive = "patient@example.test Bearer secret-token";

        var normalized = CorrelationIdMiddleware.NormalizeCorrelationId(sensitive);

        Assert.NotEqual(sensitive, normalized);
        Assert.Matches(new Regex("^[0-9a-f]{32}$"), normalized);
    }

    [Fact]
    public void CorrelationId_PreservesBoundedSafeClientId()
    {
        const string safe = "mobile-01.abc_DEF-1234";

        Assert.Equal(safe, CorrelationIdMiddleware.NormalizeCorrelationId(safe));
    }

    [Fact]
    public async Task UnhandledException_ReturnsGenericProblemWithoutExceptionMessage()
    {
        const string privateMessage =
            "patient@example.test medication=private Bearer secret-token";
        var context = new DefaultHttpContext();
        context.TraceIdentifier = "safe-correlation-1234";
        context.Response.Body = new MemoryStream();

        var middleware = new PrivacySafeExceptionMiddleware(
            _ => throw new InvalidOperationException(privateMessage),
            NullLogger<PrivacySafeExceptionMiddleware>.Instance);

        await middleware.InvokeAsync(context);
        context.Response.Body.Position = 0;
        var body = await new StreamReader(context.Response.Body).ReadToEndAsync();

        Assert.Equal(StatusCodes.Status500InternalServerError, context.Response.StatusCode);
        Assert.Equal("safe-correlation-1234", context.Response.Headers[CorrelationIdMiddleware.HeaderName]);
        Assert.Contains("internal_error", body, StringComparison.Ordinal);
        Assert.Contains("safe-correlation-1234", body, StringComparison.Ordinal);
        Assert.DoesNotContain("patient@example.test", body, StringComparison.Ordinal);
        Assert.DoesNotContain("medication=private", body, StringComparison.Ordinal);
        Assert.DoesNotContain("secret-token", body, StringComparison.Ordinal);
        Assert.DoesNotContain(nameof(InvalidOperationException), body, StringComparison.Ordinal);
    }
}

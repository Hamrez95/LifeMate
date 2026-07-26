using System.Net.Http.Headers;
using System.Security.Claims;
using System.Text.Encodings.Web;
using Microsoft.AspNetCore.Authentication;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace LifeMate.IntegrationTests;

public sealed class TestAuthHandler : AuthenticationHandler<AuthenticationSchemeOptions>
{
    public const string SchemeName = "Test";
    public const string EmailHeader = "X-Test-Email";
    public const string PhoneHeader = "X-Test-Phone";

    public TestAuthHandler(
        IOptionsMonitor<AuthenticationSchemeOptions> options,
        ILoggerFactory logger,
        UrlEncoder encoder)
        : base(options, logger, encoder)
    {
    }

    protected override Task<AuthenticateResult> HandleAuthenticateAsync()
    {
        if (!AuthenticationHeaderValue.TryParse(Request.Headers.Authorization, out var header)
            || !string.Equals(header.Scheme, SchemeName, StringComparison.Ordinal))
        {
            return Task.FromResult(AuthenticateResult.NoResult());
        }

        var subject = string.IsNullOrWhiteSpace(header.Parameter)
            ? "test-subject"
            : header.Parameter;

        var claims = new List<Claim>
        {
            new(ClaimTypes.NameIdentifier, subject),
            new("sub", subject)
        };

        AddClaimFromHeader(claims, EmailHeader, "email");
        AddClaimFromHeader(claims, PhoneHeader, "phone");

        var identity = new ClaimsIdentity(claims, SchemeName);
        var principal = new ClaimsPrincipal(identity);
        var ticket = new AuthenticationTicket(principal, SchemeName);
        return Task.FromResult(AuthenticateResult.Success(ticket));
    }

    private void AddClaimFromHeader(
        ICollection<Claim> claims,
        string headerName,
        string claimType)
    {
        var value = Request.Headers[headerName].FirstOrDefault();
        if (!string.IsNullOrWhiteSpace(value)) claims.Add(new Claim(claimType, value));
    }
}

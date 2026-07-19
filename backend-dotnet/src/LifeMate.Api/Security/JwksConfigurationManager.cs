using Microsoft.IdentityModel.Protocols;
using Microsoft.IdentityModel.Protocols.OpenIdConnect;
using Microsoft.IdentityModel.Tokens;
using System.Text.Json;

namespace LifeMate.Api.Security;

public sealed class JwksConfigurationManager : IConfigurationManager<OpenIdConnectConfiguration>
{
    private readonly string _jwksUri;
    private readonly HttpClient _httpClient = new();
    private OpenIdConnectConfiguration? _cached;
    public JwksConfigurationManager(string jwksUri) => _jwksUri = jwksUri;
    public async Task<OpenIdConnectConfiguration> GetConfigurationAsync(CancellationToken cancel)
    {
        if (_cached is not null) return _cached;
        var json = await _httpClient.GetStringAsync(_jwksUri, cancel);
        var set = new JsonWebKeySet(json);
        var configuration = new OpenIdConnectConfiguration { JwksUri = _jwksUri };
        foreach (var key in set.Keys) configuration.SigningKeys.Add(key);
        _cached = configuration;
        return configuration;
    }
    public void RequestRefresh() => _cached = null;
}

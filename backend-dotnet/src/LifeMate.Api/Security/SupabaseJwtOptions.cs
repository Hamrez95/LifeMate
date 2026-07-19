namespace LifeMate.Api.Security;
public sealed class SupabaseJwtOptions
{
    public string Issuer { get; set; } = string.Empty;
    public string Audience { get; set; } = "authenticated";
    public string? MetadataAddress { get; set; }
    public string? JwksUri { get; set; }
    public bool RequireHttpsMetadata { get; set; } = true;
}

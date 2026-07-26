namespace LifeMate.Infrastructure.Security;

public sealed class InvitationSecretOptions
{
    public const string SectionName = "Security:Invitations";

    public string ContactPepper { get; init; } = string.Empty;
}

namespace LifeMate.Application.Abstractions;

public sealed record InvitationSecret(string PlainText, string Hash);

public interface IInvitationSecretService
{
    InvitationSecret CreateToken();
    string HashToken(string plainTextToken);
    string HashContact(string canonicalContact);
}

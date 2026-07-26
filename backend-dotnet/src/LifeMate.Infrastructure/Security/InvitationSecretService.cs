using System.Security.Cryptography;
using System.Text;
using LifeMate.Application.Abstractions;
using Microsoft.Extensions.Options;

namespace LifeMate.Infrastructure.Security;

public sealed class InvitationSecretService : IInvitationSecretService
{
    private readonly byte[] _contactPepper;

    public InvitationSecretService(IOptions<InvitationSecretOptions> options)
    {
        var pepper = options.Value.ContactPepper;
        if (string.IsNullOrWhiteSpace(pepper) || Encoding.UTF8.GetByteCount(pepper) < 32)
        {
            throw new InvalidOperationException(
                "Security:Invitations:ContactPepper must contain at least 32 UTF-8 bytes.");
        }

        _contactPepper = Encoding.UTF8.GetBytes(pepper);
    }

    public InvitationSecret CreateToken()
    {
        var bytes = RandomNumberGenerator.GetBytes(32);
        var plainText = Base64UrlEncode(bytes);
        return new InvitationSecret(plainText, HashToken(plainText));
    }

    public string HashToken(string plainTextToken)
    {
        if (string.IsNullOrWhiteSpace(plainTextToken))
            throw new ArgumentException("Invitation token is required.", nameof(plainTextToken));

        var digest = SHA256.HashData(Encoding.UTF8.GetBytes(plainTextToken.Trim()));
        return Convert.ToHexString(digest).ToLowerInvariant();
    }

    public string HashContact(string canonicalContact)
    {
        if (string.IsNullOrWhiteSpace(canonicalContact))
            throw new ArgumentException("Canonical contact is required.", nameof(canonicalContact));

        using var hmac = new HMACSHA256(_contactPepper);
        var digest = hmac.ComputeHash(Encoding.UTF8.GetBytes(canonicalContact));
        return Convert.ToHexString(digest).ToLowerInvariant();
    }

    private static string Base64UrlEncode(byte[] value) =>
        Convert.ToBase64String(value)
            .TrimEnd('=')
            .Replace('+', '-')
            .Replace('/', '_');
}

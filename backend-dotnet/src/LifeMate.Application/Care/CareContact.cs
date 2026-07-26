using System.Net.Mail;
using System.Text;
using LifeMate.Domain.Care;
using LifeMate.Domain.Common;

namespace LifeMate.Application.Care;

public sealed record NormalizedCareContact(
    CareContactType Type,
    string CanonicalValue,
    string MaskedHint);

public static class CareContact
{
    public static NormalizedCareContact Normalize(CareContactType type, string value) => type switch
    {
        CareContactType.Email => NormalizeEmail(value),
        CareContactType.Phone => NormalizePhone(value),
        _ => throw new DomainException("Unsupported care invitation contact type.")
    };

    private static NormalizedCareContact NormalizeEmail(string value)
    {
        if (string.IsNullOrWhiteSpace(value)
            || !MailAddress.TryCreate(value.Trim(), out var address)
            || address.Address.Length > 320)
        {
            throw new DomainException("A valid email address is required.");
        }

        var normalized = address.Address.ToLowerInvariant();
        var at = normalized.LastIndexOf('@');
        var local = normalized[..at];
        var domain = normalized[(at + 1)..];
        var visible = local.Length <= 2 ? local[..1] : local[..2];
        var hint = $"{visible}***@{domain}";
        return new NormalizedCareContact(CareContactType.Email, $"email:{normalized}", hint);
    }

    private static NormalizedCareContact NormalizePhone(string value)
    {
        if (string.IsNullOrWhiteSpace(value))
            throw new DomainException("A valid phone number is required.");

        var latin = ConvertDigits(value.Trim());
        var compact = new string(latin.Where(c => char.IsDigit(c) || c == '+').ToArray());

        if (compact.StartsWith("0098", StringComparison.Ordinal)) compact = "+98" + compact[4..];
        else if (compact.StartsWith("98", StringComparison.Ordinal) && !compact.StartsWith('+')) compact = "+" + compact;
        else if (compact.StartsWith("09", StringComparison.Ordinal)) compact = "+98" + compact[1..];

        if (!compact.StartsWith('+')
            || compact.Count(char.IsDigit) is < 8 or > 15
            || compact.Skip(1).Any(c => !char.IsDigit(c)))
        {
            throw new DomainException("Phone number must be a valid international or Iranian mobile number.");
        }

        var suffix = compact.Length > 4 ? compact[^4..] : compact;
        return new NormalizedCareContact(CareContactType.Phone, $"phone:{compact}", $"{compact[..Math.Min(3, compact.Length)]}******{suffix}");
    }

    private static string ConvertDigits(string value)
    {
        var builder = new StringBuilder(value.Length);
        foreach (var character in value)
        {
            builder.Append(character switch
            {
                '۰' or '٠' => '0',
                '۱' or '١' => '1',
                '۲' or '٢' => '2',
                '۳' or '٣' => '3',
                '۴' or '٤' => '4',
                '۵' or '٥' => '5',
                '۶' or '٦' => '6',
                '۷' or '٧' => '7',
                '۸' or '٨' => '8',
                '۹' or '٩' => '9',
                _ => character
            });
        }

        return builder.ToString();
    }
}

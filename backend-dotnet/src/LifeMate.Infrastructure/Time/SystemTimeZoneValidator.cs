using LifeMate.Application.Abstractions;

namespace LifeMate.Infrastructure.Time;

public sealed class SystemTimeZoneValidator : ITimeZoneValidator
{
    public bool IsValid(string timeZoneId)
    {
        if (string.IsNullOrWhiteSpace(timeZoneId) || timeZoneId.Trim().Length > 64)
            return false;

        var value = timeZoneId.Trim();
        if (!value.Contains('/', StringComparison.Ordinal) && value != "UTC")
            return false;

        try
        {
            _ = TimeZoneInfo.FindSystemTimeZoneById(value);
            return true;
        }
        catch (TimeZoneNotFoundException)
        {
            return false;
        }
        catch (InvalidTimeZoneException)
        {
            return false;
        }
    }
}

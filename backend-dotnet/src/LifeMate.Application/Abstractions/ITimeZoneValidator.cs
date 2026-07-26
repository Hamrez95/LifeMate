namespace LifeMate.Application.Abstractions;

public interface ITimeZoneValidator
{
    bool IsValid(string timeZoneId);
}

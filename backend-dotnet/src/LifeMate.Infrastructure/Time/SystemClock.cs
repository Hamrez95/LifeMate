using LifeMate.Application.Abstractions;
namespace LifeMate.Infrastructure.Time;
public sealed class SystemClock : IClock { public DateTime UtcNow => DateTime.UtcNow; }

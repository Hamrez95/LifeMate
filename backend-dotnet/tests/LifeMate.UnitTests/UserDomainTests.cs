using LifeMate.Application.Users;
using LifeMate.Domain.Common;
using LifeMate.Domain.Profiles;
using LifeMate.Domain.Users;
using LifeMate.Infrastructure.Persistence;
using LifeMate.Infrastructure.Time;
using Microsoft.Data.Sqlite;
using Microsoft.EntityFrameworkCore;
using Xunit;

namespace LifeMate.UnitTests;

public sealed class UserDomainTests
{
    [Fact] public void AppUser_requires_auth_subject() => Assert.Throws<DomainException>(() => new AppUser(" ", DateTime.UtcNow));
    [Fact] public void AppUser_requires_utc_timestamps() => Assert.Throws<DomainException>(() => new AppUser("subject", DateTime.Now));
    [Fact] public void Profile_update_validates_display_name() { var p = new UserProfile(Guid.NewGuid(), "Name", null, null, null, null, DateTime.UtcNow); Assert.Throws<DomainException>(() => p.Update("", "fa", "Asia/Tehran", null, null, DateTime.UtcNow)); }
    [Fact] public async Task Bootstrap_is_idempotent()
    {
        await using var connection = new SqliteConnection("DataSource=:memory:"); await connection.OpenAsync();
        var options = new DbContextOptionsBuilder<LifeMateDbContext>().UseSqlite(connection).Options;
        await using var db = new LifeMateDbContext(options); await db.Database.EnsureCreatedAsync();
        var service = new UserService(db, new SystemClock());
        await service.BootstrapAsync(new BootstrapUserCommand("subject-1", "User", null, "user@example.test", null, null), CancellationToken.None);
        await service.BootstrapAsync(new BootstrapUserCommand("subject-1", "Other", null, null, null, null), CancellationToken.None);
        Assert.Equal(1, await db.Users.CountAsync()); Assert.Equal(1, await db.UserProfiles.CountAsync());
    }
}

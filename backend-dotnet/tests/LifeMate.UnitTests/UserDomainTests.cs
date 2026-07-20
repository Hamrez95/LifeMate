using LifeMate.Domain.Common;
using LifeMate.Domain.Profiles;
using LifeMate.Domain.Users;
using Xunit;

namespace LifeMate.UnitTests;

public sealed class UserDomainTests
{
    [Fact]
    public void AppUser_requires_auth_subject()
    {
        Assert.Throws<DomainException>(() => new AppUser(" ", DateTime.UtcNow));
    }

    [Fact]
    public void AppUser_requires_utc_timestamps()
    {
        Assert.Throws<DomainException>(() => new AppUser("subject", DateTime.Now));
    }

    [Fact]
    public void Profile_update_validates_display_name()
    {
        var profile = new UserProfile(
            Guid.NewGuid(),
            "Name",
            null,
            null,
            null,
            null,
            DateTime.UtcNow);

        Assert.Throws<DomainException>(() =>
            profile.Update("", "fa", "Asia/Tehran", null, null, DateTime.UtcNow));
    }
}

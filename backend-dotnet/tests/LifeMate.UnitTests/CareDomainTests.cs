using LifeMate.Domain.Care;
using LifeMate.Domain.Common;
using Xunit;

namespace LifeMate.UnitTests;

public sealed class CareDomainTests
{
    [Fact]
    public void Relationship_rejects_self_relationship()
    {
        var userId = Guid.NewGuid();
        Assert.Throws<DomainException>(() => new CareRelationship(userId, userId, DateTime.UtcNow, DateTime.UtcNow));
    }

    [Fact]
    public void Relationship_revocation_is_idempotent()
    {
        var now = DateTime.UtcNow;
        var relationship = new CareRelationship(Guid.NewGuid(), Guid.NewGuid(), now, now);
        relationship.Revoke(now.AddMinutes(1));
        relationship.Revoke(now.AddMinutes(2));
        Assert.Equal(CareRelationshipStatus.Revoked, relationship.Status);
        Assert.Equal(now.AddMinutes(1), relationship.RevokedAtUtc);
    }

    [Fact]
    public void Invitation_requires_future_expiry()
    {
        var now = DateTime.UtcNow;
        Assert.Throws<DomainException>(() => new CareInvitation(Guid.NewGuid(), "contact", "token", now, now));
    }

    [Fact]
    public void Invitation_cannot_be_accepted_after_expiry()
    {
        var now = DateTime.UtcNow;
        var invitation = new CareInvitation(Guid.NewGuid(), "contact", "token", now.AddMinutes(5), now);
        Assert.Throws<DomainException>(() => invitation.Accept(now.AddMinutes(6)));
        Assert.Equal(CareInvitationStatus.Expired, invitation.Status);
    }

    [Fact]
    public void Invitation_token_is_single_use_at_domain_level()
    {
        var now = DateTime.UtcNow;
        var invitation = new CareInvitation(Guid.NewGuid(), "contact", "token", now.AddHours(1), now);
        invitation.Accept(now.AddMinutes(1));
        Assert.Throws<DomainException>(() => invitation.Accept(now.AddMinutes(2)));
    }
}

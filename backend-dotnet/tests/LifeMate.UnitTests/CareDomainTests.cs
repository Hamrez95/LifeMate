using LifeMate.Application.Care;
using LifeMate.Domain.Care;
using LifeMate.Domain.Common;
using Xunit;

namespace LifeMate.UnitTests;

public sealed class CareDomainTests
{
    private const string ConsentVersion = "care-consent-v1";

    [Fact]
    public void Relationship_rejects_self_relationship()
    {
        var now = DateTime.UtcNow;
        var userId = Guid.NewGuid();

        Assert.Throws<DomainException>(() => new CareRelationship(
            userId,
            userId,
            ConsentVersion,
            now,
            ConsentVersion,
            now,
            now));
    }

    [Fact]
    public void Relationship_requires_bilateral_consent_versions()
    {
        var now = DateTime.UtcNow;

        Assert.Throws<DomainException>(() => new CareRelationship(
            Guid.NewGuid(),
            Guid.NewGuid(),
            string.Empty,
            now,
            ConsentVersion,
            now,
            now));
    }

    [Fact]
    public void Relationship_revocation_is_idempotent_for_a_participant()
    {
        var now = DateTime.UtcNow;
        var patientId = Guid.NewGuid();
        var caregiverId = Guid.NewGuid();
        var relationship = CreateRelationship(patientId, caregiverId, now);

        Assert.True(relationship.Revoke(patientId, now.AddMinutes(1)));
        Assert.False(relationship.Revoke(patientId, now.AddMinutes(2)));
        Assert.Equal(CareRelationshipStatus.Revoked, relationship.Status);
        Assert.Equal(patientId, relationship.RevokedByUserId);
        Assert.Equal(now.AddMinutes(1), relationship.RevokedAtUtc);
    }

    [Fact]
    public void Relationship_rejects_revocation_by_nonparticipant()
    {
        var now = DateTime.UtcNow;
        var relationship = CreateRelationship(Guid.NewGuid(), Guid.NewGuid(), now);

        Assert.Throws<DomainException>(() => relationship.Revoke(Guid.NewGuid(), now.AddMinutes(1)));
    }

    [Fact]
    public void Invitation_requires_future_expiry()
    {
        var now = DateTime.UtcNow;

        Assert.Throws<DomainException>(() => CreateInvitation(Guid.NewGuid(), now, now));
    }

    [Fact]
    public void Invitation_cannot_be_accepted_after_expiry()
    {
        var now = DateTime.UtcNow;
        var invitation = CreateInvitation(Guid.NewGuid(), now.AddMinutes(5), now);

        Assert.Throws<DomainException>(() => invitation.Accept(Guid.NewGuid(), now.AddMinutes(6)));
        Assert.Equal(CareInvitationStatus.Expired, invitation.Status);
    }

    [Fact]
    public void Invitation_cannot_be_accepted_by_inviter()
    {
        var now = DateTime.UtcNow;
        var inviterId = Guid.NewGuid();
        var invitation = CreateInvitation(inviterId, now.AddHours(1), now);

        Assert.Throws<DomainException>(() => invitation.Accept(inviterId, now.AddMinutes(1)));
    }

    [Fact]
    public void Invitation_token_is_single_use_at_domain_level()
    {
        var now = DateTime.UtcNow;
        var invitation = CreateInvitation(Guid.NewGuid(), now.AddHours(1), now);
        var invitee = Guid.NewGuid();

        invitation.Accept(invitee, now.AddMinutes(1));

        Assert.Throws<DomainException>(() => invitation.Accept(invitee, now.AddMinutes(2)));
    }

    [Fact]
    public void Invitation_can_be_rejected_without_creating_a_relationship()
    {
        var now = DateTime.UtcNow;
        var invitation = CreateInvitation(Guid.NewGuid(), now.AddHours(1), now);
        var invitee = Guid.NewGuid();

        invitation.Reject(invitee, now.AddMinutes(1));

        Assert.Equal(CareInvitationStatus.Rejected, invitation.Status);
        Assert.Equal(invitee, invitation.RespondedByUserId);
    }

    [Theory]
    [InlineData("Test.User@Example.COM", "email:test.user@example.com", "te***@example.com")]
    [InlineData("۰۹۱۲۱۲۳۴۵۶۷", "phone:+989121234567", "+98******4567")]
    public void Contact_normalization_is_canonical_and_masked(
        string input,
        string expectedCanonical,
        string expectedHint)
    {
        var type = input.Contains('@') ? CareContactType.Email : CareContactType.Phone;

        var result = CareContact.Normalize(type, input);

        Assert.Equal(expectedCanonical, result.CanonicalValue);
        Assert.Equal(expectedHint, result.MaskedHint);
        Assert.NotEqual(input, result.MaskedHint);
    }

    private static CareInvitation CreateInvitation(
        Guid inviterId,
        DateTime expiry,
        DateTime now) => new(
            inviterId,
            CareContactType.Email,
            "contact-hash",
            "te***@example.test",
            "token-hash",
            ConsentVersion,
            expiry,
            now);

    private static CareRelationship CreateRelationship(
        Guid patientId,
        Guid caregiverId,
        DateTime now) => new(
            patientId,
            caregiverId,
            ConsentVersion,
            now,
            ConsentVersion,
            now,
            now);
}

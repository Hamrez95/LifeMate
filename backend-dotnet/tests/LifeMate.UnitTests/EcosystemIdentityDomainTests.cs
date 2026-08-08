using LifeMate.Domain.Authorization;
using LifeMate.Domain.Commerce;
using LifeMate.Domain.Identity;
using LifeMate.Domain.People;
using Xunit;

namespace LifeMate.UnitTests;

public sealed class EcosystemIdentityDomainTests
{
    private static readonly DateTime Now = new(2026, 8, 7, 0, 0, 0, DateTimeKind.Utc);

    [Fact]
    public void Person_can_exist_without_account()
    {
        var person = new Person(Guid.NewGuid(), PersonSubjectCategory.Child, Now);

        Assert.Equal(PersonSubjectCategory.Child, person.SubjectCategory);
        Assert.Equal(PersonStatus.Active, person.Status);
    }

    [Fact]
    public void Account_and_person_are_distinct_concepts()
    {
        var accountId = Guid.NewGuid();
        var personId = Guid.NewGuid();
        var account = new Account(accountId, Now);
        var person = new Person(personId, PersonSubjectCategory.Adult, Now);
        var link = new AccountPersonLink(
            Guid.NewGuid(),
            account.Id,
            person.Id,
            AccountPersonLinkType.Self,
            Now);

        Assert.NotEqual(account.Id, person.Id);
        Assert.Equal(account.Id, link.AccountId);
        Assert.Equal(person.Id, link.PersonId);
    }

    [Fact]
    public void Guardian_link_does_not_encode_health_permission()
    {
        var link = new AccountPersonLink(
            Guid.NewGuid(),
            Guid.NewGuid(),
            Guid.NewGuid(),
            AccountPersonLinkType.Guardian,
            Now);

        Assert.Equal(AccountPersonLinkType.Guardian, link.LinkType);
        Assert.Equal(AccountPersonLinkStatus.Active, link.Status);
    }

    [Fact]
    public void Access_grant_scopes_are_contextual_and_revocable()
    {
        var grant = new AccessGrant(
            Guid.NewGuid(),
            Guid.NewGuid(),
            Guid.NewGuid(),
            "care_relationship",
            Guid.NewGuid(),
            Now,
            Now.AddDays(7));
        grant.GrantScope("treatment.adherence.read");

        Assert.True(grant.HasScope("treatment.adherence.read", Now.AddHours(1)));
        Assert.False(grant.HasScope("women_health.summary.read", Now.AddHours(1)));

        grant.Revoke();
        Assert.False(grant.HasScope("treatment.adherence.read", Now.AddHours(1)));
    }

    [Fact]
    public void Entitlement_can_separate_grantee_from_beneficiary()
    {
        var accountId = Guid.NewGuid();
        var childPersonId = Guid.NewGuid();
        var entitlement = new Entitlement(
            Guid.NewGuid(),
            "baby.advanced_tracking",
            EntitlementSource.Subscription,
            "subscription:test",
            Now,
            granteeAccountId: accountId,
            beneficiaryPersonId: childPersonId,
            expiresAtUtc: Now.AddMonths(1));

        Assert.Equal(accountId, entitlement.GranteeAccountId);
        Assert.Equal(childPersonId, entitlement.BeneficiaryPersonId);
        Assert.True(entitlement.IsActiveAt(Now.AddDays(1)));
        Assert.False(entitlement.IsActiveAt(Now.AddMonths(2)));
    }

    [Fact]
    public void External_identity_is_keyed_by_provider_issuer_and_subject_not_email()
    {
        var identity = new ExternalIdentity(
            Guid.NewGuid(),
            Guid.NewGuid(),
            "google",
            "https://accounts.google.com",
            "google-oidc-subject",
            Now);

        Assert.Equal("google-oidc-subject", identity.ProviderSubject);
        Assert.Equal("https://accounts.google.com", identity.Issuer);
    }
}

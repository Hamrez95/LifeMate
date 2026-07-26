using System.Text.Json;
using LifeMate.Application.Abstractions;
using LifeMate.Domain.Audit;
using LifeMate.Domain.Care;
using LifeMate.Domain.Common;
using LifeMate.Domain.Users;
using Microsoft.EntityFrameworkCore;

namespace LifeMate.Application.Care;

public sealed class CareService
{
    private static readonly TimeSpan InvitationLifetime = TimeSpan.FromHours(72);

    private readonly IAppDbContext _db;
    private readonly IClock _clock;
    private readonly IInvitationSecretService _secrets;

    public CareService(IAppDbContext db, IClock clock, IInvitationSecretService secrets)
    {
        _db = db;
        _clock = clock;
        _secrets = secrets;
    }

    public async Task<CareResult<CareInvitationCreatedDto>> CreateInvitationAsync(
        CreateCareInvitationCommand command,
        CancellationToken cancellationToken)
    {
        if (!command.ConfirmedPatientConsent || string.IsNullOrWhiteSpace(command.PatientConsentVersion))
        {
            return CareResult<CareInvitationCreatedDto>.Failure(
                CareErrorKind.Validation,
                "patient_consent_required",
                "The patient must explicitly consent before inviting a caregiver.");
        }

        NormalizedCareContact contact;
        try
        {
            contact = CareContact.Normalize(command.ContactType, command.Contact);
        }
        catch (DomainException exception)
        {
            return CareResult<CareInvitationCreatedDto>.Failure(
                CareErrorKind.Validation,
                "invalid_contact",
                exception.Message);
        }

        var user = await FindActiveUserAsync(command.Identity.AuthSubject, cancellationToken);
        if (user is null) return NotOnboarded<CareInvitationCreatedDto>();

        var contactHash = _secrets.HashContact(contact.CanonicalValue);
        if (GetIdentityContactHashes(command.Identity).Contains(contactHash))
        {
            return CareResult<CareInvitationCreatedDto>.Failure(
                CareErrorKind.Validation,
                "self_invitation_not_allowed",
                "You cannot invite your own authenticated contact.");
        }

        var now = _clock.UtcNow;
        var existing = await _db.CareInvitations
            .Where(x => x.InviterUserId == user.Id
                && x.ContactHash == contactHash
                && x.Status == CareInvitationStatus.Pending)
            .ToListAsync(cancellationToken);

        var expiredChanged = false;
        foreach (var stale in existing.Where(x => x.IsExpired(now)))
        {
            expiredChanged |= stale.Expire(now);
        }

        if (existing.Any(x => x.Status == CareInvitationStatus.Pending))
        {
            return CareResult<CareInvitationCreatedDto>.Failure(
                CareErrorKind.Conflict,
                "invitation_already_pending",
                "A pending invitation already exists for this contact.");
        }

        var token = _secrets.CreateToken();
        var invitation = new CareInvitation(
            user.Id,
            contact.Type,
            contactHash,
            contact.MaskedHint,
            token.Hash,
            command.PatientConsentVersion,
            now.Add(InvitationLifetime),
            now);

        _db.CareInvitations.Add(invitation);
        _db.AuditLogs.Add(new AuditLog(
            user.Id,
            "care_invitation.created",
            "care_invitation",
            invitation.Id,
            JsonSerializer.Serialize(new { invitation.ExpiresAtUtc, invitation.ContactType }),
            now));

        try
        {
            await _db.SaveChangesAsync(cancellationToken);
        }
        catch (DbUpdateException)
        {
            return CareResult<CareInvitationCreatedDto>.Failure(
                CareErrorKind.Conflict,
                "invitation_conflict",
                "The invitation could not be created because a conflicting request already exists.");
        }

        _ = expiredChanged;
        return CareResult<CareInvitationCreatedDto>.Success(new CareInvitationCreatedDto(
            invitation.Id,
            invitation.ContactType,
            invitation.ContactHint,
            token.PlainText,
            invitation.ExpiresAtUtc));
    }

    public async Task<CareResult<IReadOnlyList<CareInvitationDto>>> ListOutgoingInvitationsAsync(
        AuthenticatedCareIdentity identity,
        CancellationToken cancellationToken)
    {
        var user = await FindActiveUserAsync(identity.AuthSubject, cancellationToken);
        if (user is null) return NotOnboarded<IReadOnlyList<CareInvitationDto>>();

        var now = _clock.UtcNow;
        var invitations = await _db.CareInvitations
            .AsNoTracking()
            .Where(x => x.InviterUserId == user.Id)
            .OrderByDescending(x => x.CreatedAtUtc)
            .Take(100)
            .ToListAsync(cancellationToken);

        IReadOnlyList<CareInvitationDto> result = invitations
            .Select(x => MapInvitation(x, now))
            .ToList();

        return CareResult<IReadOnlyList<CareInvitationDto>>.Success(result);
    }

    public async Task<CareResult<CareRelationshipDto>> AcceptInvitationAsync(
        AcceptCareInvitationCommand command,
        CancellationToken cancellationToken)
    {
        if (!command.ConfirmedCaregiverConsent || string.IsNullOrWhiteSpace(command.CaregiverConsentVersion))
        {
            return CareResult<CareRelationshipDto>.Failure(
                CareErrorKind.Validation,
                "caregiver_consent_required",
                "The caregiver must explicitly consent before accepting access.");
        }

        var access = await ResolveInvitationAsync(command.Identity, command.Token, cancellationToken);
        if (!access.Succeeded)
        {
            return CareResult<CareRelationshipDto>.Failure(
                access.ErrorKind!.Value,
                access.ErrorCode!,
                access.ErrorMessage!);
        }

        var context = access.Value!;
        var activeRelationship = await _db.CareRelationships.SingleOrDefaultAsync(
            x => x.PatientUserId == context.Invitation.InviterUserId
                && x.CaregiverUserId == context.User.Id
                && x.Status == CareRelationshipStatus.Active,
            cancellationToken);

        if (activeRelationship is not null)
        {
            return CareResult<CareRelationshipDto>.Failure(
                CareErrorKind.Conflict,
                "relationship_already_active",
                "An active care relationship already exists.");
        }

        try
        {
            context.Invitation.Accept(context.User.Id, context.Now);
            var relationship = new CareRelationship(
                context.Invitation.InviterUserId,
                context.User.Id,
                context.Invitation.PatientConsentVersion,
                context.Invitation.CreatedAtUtc,
                command.CaregiverConsentVersion,
                context.Now,
                context.Now);

            _db.CareRelationships.Add(relationship);
            _db.AuditLogs.Add(new AuditLog(
                context.User.Id,
                "care_invitation.accepted",
                "care_invitation",
                context.Invitation.Id,
                null,
                context.Now));
            _db.AuditLogs.Add(new AuditLog(
                context.User.Id,
                "care_relationship.created",
                "care_relationship",
                relationship.Id,
                JsonSerializer.Serialize(new
                {
                    relationship.PatientUserId,
                    relationship.CaregiverUserId
                }),
                context.Now));

            await _db.SaveChangesAsync(cancellationToken);
            return CareResult<CareRelationshipDto>.Success(
                await MapRelationshipAsync(relationship, cancellationToken));
        }
        catch (DomainException exception)
        {
            return CareResult<CareRelationshipDto>.Failure(
                CareErrorKind.Conflict,
                "invitation_not_actionable",
                exception.Message);
        }
        catch (DbUpdateException)
        {
            return CareResult<CareRelationshipDto>.Failure(
                CareErrorKind.Conflict,
                "relationship_conflict",
                "The invitation response conflicted with another request.");
        }
    }

    public async Task<CareResult<CareInvitationDto>> RejectInvitationAsync(
        RejectCareInvitationCommand command,
        CancellationToken cancellationToken)
    {
        var access = await ResolveInvitationAsync(command.Identity, command.Token, cancellationToken);
        if (!access.Succeeded)
        {
            return CareResult<CareInvitationDto>.Failure(
                access.ErrorKind!.Value,
                access.ErrorCode!,
                access.ErrorMessage!);
        }

        var context = access.Value!;
        try
        {
            context.Invitation.Reject(context.User.Id, context.Now);
            _db.AuditLogs.Add(new AuditLog(
                context.User.Id,
                "care_invitation.rejected",
                "care_invitation",
                context.Invitation.Id,
                null,
                context.Now));
            await _db.SaveChangesAsync(cancellationToken);
            return CareResult<CareInvitationDto>.Success(MapInvitation(context.Invitation, context.Now));
        }
        catch (DomainException exception)
        {
            return CareResult<CareInvitationDto>.Failure(
                CareErrorKind.Conflict,
                "invitation_not_actionable",
                exception.Message);
        }
    }

    public async Task<CareResult<IReadOnlyList<CareRelationshipDto>>> ListRelationshipsAsync(
        AuthenticatedCareIdentity identity,
        CancellationToken cancellationToken)
    {
        var user = await FindActiveUserAsync(identity.AuthSubject, cancellationToken);
        if (user is null) return NotOnboarded<IReadOnlyList<CareRelationshipDto>>();

        var rows = await (
            from relationship in _db.CareRelationships.AsNoTracking()
            join patientProfile in _db.UserProfiles.AsNoTracking()
                on relationship.PatientUserId equals patientProfile.UserId
            join caregiverProfile in _db.UserProfiles.AsNoTracking()
                on relationship.CaregiverUserId equals caregiverProfile.UserId
            where relationship.PatientUserId == user.Id || relationship.CaregiverUserId == user.Id
            orderby relationship.CreatedAtUtc descending
            select new CareRelationshipDto(
                relationship.Id,
                relationship.PatientUserId,
                patientProfile.DisplayName,
                relationship.CaregiverUserId,
                caregiverProfile.DisplayName,
                relationship.Status.ToString().ToLowerInvariant(),
                relationship.PatientConsentedAtUtc,
                relationship.CaregiverConsentedAtUtc,
                relationship.RevokedAtUtc,
                relationship.CreatedAtUtc))
            .Take(100)
            .ToListAsync(cancellationToken);

        return CareResult<IReadOnlyList<CareRelationshipDto>>.Success(rows);
    }

    public async Task<CareResult<CareInvitationDto>> RevokeInvitationAsync(
        AuthenticatedCareIdentity identity,
        Guid invitationId,
        CancellationToken cancellationToken)
    {
        var user = await FindActiveUserAsync(identity.AuthSubject, cancellationToken);
        if (user is null) return NotOnboarded<CareInvitationDto>();

        var invitation = await _db.CareInvitations.SingleOrDefaultAsync(
            x => x.Id == invitationId && x.InviterUserId == user.Id,
            cancellationToken);

        if (invitation is null)
        {
            return CareResult<CareInvitationDto>.Failure(
                CareErrorKind.NotFound,
                "invitation_not_found",
                "Invitation was not found.");
        }

        var now = _clock.UtcNow;
        try
        {
            if (invitation.Revoke(now))
            {
                _db.AuditLogs.Add(new AuditLog(
                    user.Id,
                    "care_invitation.revoked",
                    "care_invitation",
                    invitation.Id,
                    null,
                    now));
                await _db.SaveChangesAsync(cancellationToken);
            }
        }
        catch (DomainException exception)
        {
            return CareResult<CareInvitationDto>.Failure(
                CareErrorKind.Conflict,
                "invitation_not_revocable",
                exception.Message);
        }

        return CareResult<CareInvitationDto>.Success(MapInvitation(invitation, now));
    }

    public async Task<CareResult<CareRelationshipDto>> RevokeRelationshipAsync(
        AuthenticatedCareIdentity identity,
        Guid relationshipId,
        CancellationToken cancellationToken)
    {
        var user = await FindActiveUserAsync(identity.AuthSubject, cancellationToken);
        if (user is null) return NotOnboarded<CareRelationshipDto>();

        var relationship = await _db.CareRelationships.SingleOrDefaultAsync(
            x => x.Id == relationshipId
                && (x.PatientUserId == user.Id || x.CaregiverUserId == user.Id),
            cancellationToken);

        if (relationship is null)
        {
            return CareResult<CareRelationshipDto>.Failure(
                CareErrorKind.NotFound,
                "relationship_not_found",
                "Care relationship was not found.");
        }

        var now = _clock.UtcNow;
        try
        {
            if (relationship.Revoke(user.Id, now))
            {
                _db.AuditLogs.Add(new AuditLog(
                    user.Id,
                    "care_relationship.revoked",
                    "care_relationship",
                    relationship.Id,
                    null,
                    now));
                await _db.SaveChangesAsync(cancellationToken);
            }
        }
        catch (DomainException exception)
        {
            return CareResult<CareRelationshipDto>.Failure(
                CareErrorKind.Forbidden,
                "relationship_revoke_forbidden",
                exception.Message);
        }

        return CareResult<CareRelationshipDto>.Success(
            await MapRelationshipAsync(relationship, cancellationToken));
    }

    private async Task<CareResult<InvitationAccess>> ResolveInvitationAsync(
        AuthenticatedCareIdentity identity,
        string token,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(token) || token.Length > 512)
        {
            return CareResult<InvitationAccess>.Failure(
                CareErrorKind.Validation,
                "invalid_invitation_token",
                "Invitation token is invalid.");
        }

        var user = await FindActiveUserAsync(identity.AuthSubject, cancellationToken);
        if (user is null) return NotOnboarded<InvitationAccess>();

        var tokenHash = _secrets.HashToken(token.Trim());
        var invitation = await _db.CareInvitations.SingleOrDefaultAsync(
            x => x.TokenHash == tokenHash,
            cancellationToken);

        if (invitation is null)
        {
            return CareResult<InvitationAccess>.Failure(
                CareErrorKind.NotFound,
                "invitation_not_found",
                "Invitation is invalid or no longer available.");
        }

        var now = _clock.UtcNow;
        if (invitation.IsExpired(now))
        {
            if (invitation.Expire(now)) await _db.SaveChangesAsync(cancellationToken);
            return CareResult<InvitationAccess>.Failure(
                CareErrorKind.Gone,
                "invitation_expired",
                "Invitation has expired.");
        }

        if (invitation.Status != CareInvitationStatus.Pending)
        {
            return CareResult<InvitationAccess>.Failure(
                CareErrorKind.Conflict,
                "invitation_not_pending",
                "Invitation has already been responded to or revoked.");
        }

        if (!GetIdentityContactHashes(identity).Contains(invitation.ContactHash))
        {
            return CareResult<InvitationAccess>.Failure(
                CareErrorKind.Forbidden,
                "invitation_contact_mismatch",
                "This invitation was issued to a different authenticated contact.");
        }

        return CareResult<InvitationAccess>.Success(new InvitationAccess(user, invitation, now));
    }

    private async Task<AppUser?> FindActiveUserAsync(
        string authSubject,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(authSubject)) return null;

        return await _db.Users.SingleOrDefaultAsync(
            x => x.AuthSubject == authSubject.Trim() && x.Status == AppUserStatus.Active,
            cancellationToken);
    }

    private HashSet<string> GetIdentityContactHashes(AuthenticatedCareIdentity identity)
    {
        var hashes = new HashSet<string>(StringComparer.Ordinal);
        TryAddIdentityContact(hashes, CareContactType.Email, identity.Email);
        TryAddIdentityContact(hashes, CareContactType.Phone, identity.PhoneNumber);
        return hashes;
    }

    private void TryAddIdentityContact(
        HashSet<string> hashes,
        CareContactType type,
        string? value)
    {
        if (string.IsNullOrWhiteSpace(value)) return;

        try
        {
            hashes.Add(_secrets.HashContact(CareContact.Normalize(type, value).CanonicalValue));
        }
        catch (DomainException)
        {
            // Invalid optional identity claims are ignored; a valid matching claim remains mandatory.
        }
    }

    private async Task<CareRelationshipDto> MapRelationshipAsync(
        CareRelationship relationship,
        CancellationToken cancellationToken)
    {
        var names = await _db.UserProfiles
            .AsNoTracking()
            .Where(x => x.UserId == relationship.PatientUserId || x.UserId == relationship.CaregiverUserId)
            .ToDictionaryAsync(x => x.UserId, x => x.DisplayName, cancellationToken);

        return new CareRelationshipDto(
            relationship.Id,
            relationship.PatientUserId,
            names.GetValueOrDefault(relationship.PatientUserId, "LifeMate User"),
            relationship.CaregiverUserId,
            names.GetValueOrDefault(relationship.CaregiverUserId, "LifeMate User"),
            relationship.Status.ToString().ToLowerInvariant(),
            relationship.PatientConsentedAtUtc,
            relationship.CaregiverConsentedAtUtc,
            relationship.RevokedAtUtc,
            relationship.CreatedAtUtc);
    }

    private static CareInvitationDto MapInvitation(CareInvitation invitation, DateTime utcNow) =>
        new(
            invitation.Id,
            invitation.ContactType,
            invitation.ContactHint,
            invitation.Status == CareInvitationStatus.Pending && invitation.IsExpired(utcNow)
                ? CareInvitationStatus.Expired.ToString().ToLowerInvariant()
                : invitation.Status.ToString().ToLowerInvariant(),
            invitation.ExpiresAtUtc,
            invitation.CreatedAtUtc);

    private static CareResult<T> NotOnboarded<T>() => CareResult<T>.Failure(
        CareErrorKind.NotFound,
        "not_onboarded",
        "Bootstrap is required before using care relationships.");

    private sealed record InvitationAccess(
        AppUser User,
        CareInvitation Invitation,
        DateTime Now);
}

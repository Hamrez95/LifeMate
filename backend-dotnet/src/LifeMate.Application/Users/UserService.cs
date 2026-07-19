using LifeMate.Application.Abstractions;
using LifeMate.Domain.Audit;
using LifeMate.Domain.Common;
using LifeMate.Domain.Profiles;
using LifeMate.Domain.Users;
using Microsoft.EntityFrameworkCore;

namespace LifeMate.Application.Users;

public sealed class UserService
{
    private readonly IAppDbContext _db; private readonly IClock _clock;
    public UserService(IAppDbContext db, IClock clock) { _db = db; _clock = clock; }
    public async Task<CurrentUserDto> BootstrapAsync(BootstrapUserCommand command, CancellationToken ct)
    {
        var subject = NormalizeSubject(command.AuthSubject);
        var user = await _db.Users.SingleOrDefaultAsync(x => x.AuthSubject == subject, ct);
        if (user is null) { user = new AppUser(subject, _clock.UtcNow); _db.Users.Add(user); await _db.SaveChangesAsync(ct); }
        var profile = await _db.UserProfiles.SingleOrDefaultAsync(x => x.UserId == user.Id, ct);
        if (profile is null)
        {
            profile = new UserProfile(user.Id, command.DisplayName ?? "LifeMate User", command.PhoneNumber, command.Email, command.Locale, command.TimeZone, _clock.UtcNow);
            _db.UserProfiles.Add(profile);
            _db.AuditLogs.Add(new AuditLog(user.Id, "user.bootstrap", "app_user", user.Id, null, _clock.UtcNow));
            await _db.SaveChangesAsync(ct);
        }
        return Map(user, profile);
    }
    public async Task<OperationResult<CurrentUserDto>> GetMeAsync(string authSubject, CancellationToken ct)
    {
        var subject = NormalizeSubject(authSubject);
        var user = await _db.Users.SingleOrDefaultAsync(x => x.AuthSubject == subject, ct);
        if (user is null) return OperationResult<CurrentUserDto>.NotFound("not_onboarded", "The authenticated subject has not been bootstrapped.");
        var profile = await _db.UserProfiles.SingleOrDefaultAsync(x => x.UserId == user.Id, ct);
        if (profile is null) return OperationResult<CurrentUserDto>.NotFound("profile_missing", "The authenticated user does not have a profile.");
        return OperationResult<CurrentUserDto>.Success(Map(user, profile));
    }
    public async Task<OperationResult<CurrentUserDto>> UpdateProfileAsync(UpdateProfileCommand command, CancellationToken ct)
    {
        var current = await _db.Users.SingleOrDefaultAsync(x => x.AuthSubject == NormalizeSubject(command.AuthSubject), ct);
        if (current is null) return OperationResult<CurrentUserDto>.NotFound("not_onboarded", "Bootstrap is required before updating a profile.");
        var profile = await _db.UserProfiles.SingleOrDefaultAsync(x => x.UserId == current.Id, ct);
        if (profile is null) return OperationResult<CurrentUserDto>.NotFound("profile_missing", "Bootstrap is required before updating a profile.");
        try { profile.Update(command.DisplayName, command.Locale, command.TimeZone, command.PhoneNumber, command.Email, _clock.UtcNow); }
        catch (DomainException ex) { return OperationResult<CurrentUserDto>.Validation("invalid_profile", ex.Message); }
        _db.AuditLogs.Add(new AuditLog(current.Id, "user_profile.update", "user_profile", profile.Id, null, _clock.UtcNow));
        await _db.SaveChangesAsync(ct);
        return OperationResult<CurrentUserDto>.Success(Map(current, profile));
    }
    private static string NormalizeSubject(string subject) => string.IsNullOrWhiteSpace(subject) ? throw new DomainException("Authenticated subject is required.") : subject.Trim();
    private static CurrentUserDto Map(AppUser user, UserProfile profile) => new(new AppUserDto(user.Id, user.AuthSubject, user.Status.ToString().ToLowerInvariant(), user.CreatedAtUtc, user.UpdatedAtUtc), new UserProfileDto(profile.Id, profile.UserId, profile.DisplayName, profile.PhoneNumber, profile.Email, profile.Locale, profile.TimeZone));
}

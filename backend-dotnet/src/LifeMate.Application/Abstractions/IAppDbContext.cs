using LifeMate.Domain.Audit;
using LifeMate.Domain.Care;
using LifeMate.Domain.Consents;
using LifeMate.Domain.Profiles;
using LifeMate.Domain.Users;
using Microsoft.EntityFrameworkCore;

namespace LifeMate.Application.Abstractions;

public interface IAppDbContext
{
    DbSet<AppUser> Users { get; }
    DbSet<UserProfile> UserProfiles { get; }
    DbSet<PrivacyConsent> PrivacyConsents { get; }
    DbSet<AuditLog> AuditLogs { get; }
    DbSet<CareInvitation> CareInvitations { get; }
    DbSet<CareRelationship> CareRelationships { get; }
    Task<int> SaveChangesAsync(CancellationToken cancellationToken = default);
}

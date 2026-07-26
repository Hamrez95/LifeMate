using LifeMate.Domain.Adherence;
using LifeMate.Domain.Audit;
using LifeMate.Domain.Care;
using LifeMate.Domain.Consents;
using LifeMate.Domain.Profiles;
using LifeMate.Domain.Treatments;
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
    DbSet<Medication> Medications { get; }
    DbSet<TreatmentPlan> TreatmentPlans { get; }
    DbSet<TreatmentSchedule> TreatmentSchedules { get; }
    DbSet<DoseOccurrence> DoseOccurrences { get; }
    DbSet<DoseAdherenceEvent> DoseAdherenceEvents { get; }
    Task<int> SaveChangesAsync(CancellationToken cancellationToken = default);
}

using LifeMate.Application.Abstractions;
using LifeMate.Domain.Audit;
using LifeMate.Domain.Care;
using LifeMate.Domain.Consents;
using LifeMate.Domain.Profiles;
using LifeMate.Domain.Users;
using Microsoft.EntityFrameworkCore;

namespace LifeMate.Infrastructure.Persistence;

public sealed class LifeMateDbContext : DbContext, IAppDbContext
{
    public LifeMateDbContext(DbContextOptions<LifeMateDbContext> options) : base(options) { }

    public DbSet<AppUser> Users => Set<AppUser>();
    public DbSet<UserProfile> UserProfiles => Set<UserProfile>();
    public DbSet<PrivacyConsent> PrivacyConsents => Set<PrivacyConsent>();
    public DbSet<AuditLog> AuditLogs => Set<AuditLog>();
    public DbSet<CareInvitation> CareInvitations => Set<CareInvitation>();
    public DbSet<CareRelationship> CareRelationships => Set<CareRelationship>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.HasDefaultSchema("lifemate");

        modelBuilder.Entity<AppUser>(b =>
        {
            b.ToTable("app_users");
            b.HasKey(x => x.Id);
            b.Property(x => x.Id).HasColumnName("id");
            b.Property(x => x.AuthSubject).HasColumnName("auth_subject").HasMaxLength(256).IsRequired();
            b.HasIndex(x => x.AuthSubject).IsUnique();
            b.Property(x => x.Status).HasColumnName("status").HasConversion<string>().HasMaxLength(32);
            b.Property(x => x.CreatedAtUtc).HasColumnName("created_at_utc");
            b.Property(x => x.UpdatedAtUtc).HasColumnName("updated_at_utc");
        });

        modelBuilder.Entity<UserProfile>(b =>
        {
            b.ToTable("user_profiles");
            b.HasKey(x => x.Id);
            b.Property(x => x.Id).HasColumnName("id");
            b.Property(x => x.UserId).HasColumnName("user_id");
            b.HasIndex(x => x.UserId).IsUnique();
            b.HasOne<AppUser>().WithOne().HasForeignKey<UserProfile>(x => x.UserId).OnDelete(DeleteBehavior.Restrict);
            b.Property(x => x.DisplayName).HasColumnName("display_name").HasMaxLength(120);
            b.Property(x => x.PhoneNumber).HasColumnName("phone_number").HasMaxLength(32);
            b.HasIndex(x => x.PhoneNumber);
            b.Property(x => x.Email).HasColumnName("email").HasMaxLength(320);
            b.HasIndex(x => x.Email);
            b.Property(x => x.Locale).HasColumnName("locale").HasMaxLength(16).HasDefaultValue(UserProfile.DefaultLocale);
            b.Property(x => x.TimeZone).HasColumnName("time_zone").HasMaxLength(64).HasDefaultValue(UserProfile.DefaultTimeZone);
            b.Property(x => x.CreatedAtUtc).HasColumnName("created_at_utc");
            b.Property(x => x.UpdatedAtUtc).HasColumnName("updated_at_utc");
        });

        modelBuilder.Entity<PrivacyConsent>(b =>
        {
            b.ToTable("privacy_consents");
            b.HasKey(x => x.Id);
            b.Property(x => x.UserId).HasColumnName("user_id");
            b.HasOne<AppUser>().WithMany().HasForeignKey(x => x.UserId).OnDelete(DeleteBehavior.Restrict);
            b.Property(x => x.DocumentType).HasColumnName("document_type").HasConversion<string>().HasMaxLength(32);
            b.Property(x => x.DocumentVersion).HasColumnName("document_version").HasMaxLength(64);
            b.Property(x => x.GrantedAtUtc).HasColumnName("granted_at_utc");
            b.Property(x => x.RevokedAtUtc).HasColumnName("revoked_at_utc");
            b.Property(x => x.CreatedAtUtc).HasColumnName("created_at_utc");
            b.HasIndex(x => new { x.UserId, x.DocumentType, x.DocumentVersion });
        });

        modelBuilder.Entity<AuditLog>(b =>
        {
            b.ToTable("audit_logs");
            b.HasKey(x => x.Id);
            b.Property(x => x.ActorUserId).HasColumnName("actor_user_id");
            b.HasOne<AppUser>().WithMany().HasForeignKey(x => x.ActorUserId).OnDelete(DeleteBehavior.SetNull);
            b.Property(x => x.Action).HasColumnName("action").HasMaxLength(128);
            b.Property(x => x.ResourceType).HasColumnName("resource_type").HasMaxLength(128);
            b.Property(x => x.ResourceId).HasColumnName("resource_id");
            b.Property(x => x.MetadataJson).HasColumnName("metadata_json").HasColumnType("jsonb");
            b.Property(x => x.CreatedAtUtc).HasColumnName("created_at_utc");
            b.HasIndex(x => x.ActorUserId);
            b.HasIndex(x => new { x.ResourceType, x.ResourceId });
            b.HasIndex(x => x.CreatedAtUtc);
        });

        modelBuilder.Entity<CareInvitation>(b =>
        {
            b.ToTable("care_invitations");
            b.HasKey(x => x.Id);
            b.Property(x => x.InviterUserId).HasColumnName("inviter_user_id");
            b.HasOne<AppUser>().WithMany().HasForeignKey(x => x.InviterUserId).OnDelete(DeleteBehavior.Restrict);
            b.Property(x => x.ContactType).HasColumnName("contact_type").HasConversion<string>().HasMaxLength(16);
            b.Property(x => x.ContactHash).HasColumnName("contact_hash").HasMaxLength(128).IsRequired();
            b.Property(x => x.ContactHint).HasColumnName("contact_hint").HasMaxLength(160).IsRequired();
            b.Property(x => x.TokenHash).HasColumnName("token_hash").HasMaxLength(128).IsRequired();
            b.Property(x => x.PatientConsentVersion).HasColumnName("patient_consent_version").HasMaxLength(64).IsRequired();
            b.Property(x => x.Status).HasColumnName("status").HasConversion<string>().HasMaxLength(32);
            b.Property(x => x.ExpiresAtUtc).HasColumnName("expires_at_utc");
            b.Property(x => x.RespondedByUserId).HasColumnName("responded_by_user_id");
            b.HasOne<AppUser>().WithMany().HasForeignKey(x => x.RespondedByUserId).OnDelete(DeleteBehavior.Restrict);
            b.Property(x => x.RespondedAtUtc).HasColumnName("responded_at_utc");
            b.Property(x => x.RevokedAtUtc).HasColumnName("revoked_at_utc");
            b.Property(x => x.CreatedAtUtc).HasColumnName("created_at_utc");
            b.HasIndex(x => x.TokenHash).IsUnique();
            b.HasIndex(x => new { x.InviterUserId, x.ContactHash })
                .HasFilter("\"status\" = 'Pending'")
                .IsUnique();
            b.HasIndex(x => x.ExpiresAtUtc);
        });

        modelBuilder.Entity<CareRelationship>(b =>
        {
            b.ToTable("care_relationships");
            b.HasKey(x => x.Id);
            b.Property(x => x.PatientUserId).HasColumnName("patient_user_id");
            b.Property(x => x.CaregiverUserId).HasColumnName("caregiver_user_id");
            b.HasOne<AppUser>().WithMany().HasForeignKey(x => x.PatientUserId).OnDelete(DeleteBehavior.Restrict);
            b.HasOne<AppUser>().WithMany().HasForeignKey(x => x.CaregiverUserId).OnDelete(DeleteBehavior.Restrict);
            b.Property(x => x.Status).HasColumnName("status").HasConversion<string>().HasMaxLength(32);
            b.Property(x => x.PatientConsentVersion).HasColumnName("patient_consent_version").HasMaxLength(64).IsRequired();
            b.Property(x => x.PatientConsentedAtUtc).HasColumnName("patient_consented_at_utc");
            b.Property(x => x.CaregiverConsentVersion).HasColumnName("caregiver_consent_version").HasMaxLength(64).IsRequired();
            b.Property(x => x.CaregiverConsentedAtUtc).HasColumnName("caregiver_consented_at_utc");
            b.Property(x => x.RevokedByUserId).HasColumnName("revoked_by_user_id");
            b.HasOne<AppUser>().WithMany().HasForeignKey(x => x.RevokedByUserId).OnDelete(DeleteBehavior.Restrict);
            b.Property(x => x.RevokedAtUtc).HasColumnName("revoked_at_utc");
            b.Property(x => x.CreatedAtUtc).HasColumnName("created_at_utc");
            b.Property(x => x.UpdatedAtUtc).HasColumnName("updated_at_utc");
            b.HasIndex(x => new { x.PatientUserId, x.CaregiverUserId })
                .HasFilter("\"status\" = 'Active'")
                .IsUnique();
            b.HasIndex(x => x.CaregiverUserId);
        });
    }
}

using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace LifeMate.Infrastructure.Persistence.Migrations;

public partial class InitialIdentityFoundation : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.EnsureSchema(name: "lifemate");
        migrationBuilder.CreateTable(name: "app_users", schema: "lifemate", columns: table => new
        {
            id = table.Column<Guid>(type: "uuid", nullable: false),
            auth_subject = table.Column<string>(type: "character varying(256)", maxLength: 256, nullable: false),
            status = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: false),
            created_at_utc = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
            updated_at_utc = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
        }, constraints: table => table.PrimaryKey("pk_app_users", x => x.id));
        migrationBuilder.CreateTable(name: "audit_logs", schema: "lifemate", columns: table => new
        {
            id = table.Column<Guid>(type: "uuid", nullable: false), actor_user_id = table.Column<Guid>(type: "uuid", nullable: true), action = table.Column<string>(type: "character varying(128)", maxLength: 128, nullable: false), resource_type = table.Column<string>(type: "character varying(128)", maxLength: 128, nullable: false), resource_id = table.Column<Guid>(type: "uuid", nullable: true), metadata_json = table.Column<string>(type: "jsonb", nullable: true), created_at_utc = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
        }, constraints: table => { table.PrimaryKey("pk_audit_logs", x => x.id); table.ForeignKey("fk_audit_logs_app_users_actor_user_id", x => x.actor_user_id, "app_users", "id", "lifemate", onDelete: ReferentialAction.SetNull); });
        migrationBuilder.CreateTable(name: "privacy_consents", schema: "lifemate", columns: table => new
        {
            id = table.Column<Guid>(type: "uuid", nullable: false), user_id = table.Column<Guid>(type: "uuid", nullable: false), document_type = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: false), document_version = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false), granted_at_utc = table.Column<DateTime>(type: "timestamp with time zone", nullable: false), revoked_at_utc = table.Column<DateTime>(type: "timestamp with time zone", nullable: true), created_at_utc = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
        }, constraints: table => { table.PrimaryKey("pk_privacy_consents", x => x.id); table.ForeignKey("fk_privacy_consents_app_users_user_id", x => x.user_id, "app_users", "id", "lifemate", onDelete: ReferentialAction.Restrict); });
        migrationBuilder.CreateTable(name: "user_profiles", schema: "lifemate", columns: table => new
        {
            id = table.Column<Guid>(type: "uuid", nullable: false), user_id = table.Column<Guid>(type: "uuid", nullable: false), display_name = table.Column<string>(type: "character varying(120)", maxLength: 120, nullable: false), phone_number = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: true), email = table.Column<string>(type: "character varying(320)", maxLength: 320, nullable: true), locale = table.Column<string>(type: "character varying(16)", maxLength: 16, nullable: false, defaultValue: "fa"), time_zone = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false, defaultValue: "Asia/Tehran"), created_at_utc = table.Column<DateTime>(type: "timestamp with time zone", nullable: false), updated_at_utc = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
        }, constraints: table => { table.PrimaryKey("pk_user_profiles", x => x.id); table.ForeignKey("fk_user_profiles_app_users_user_id", x => x.user_id, "app_users", "id", "lifemate", onDelete: ReferentialAction.Restrict); });
        migrationBuilder.CreateIndex("ix_app_users_auth_subject", "app_users", "auth_subject", "lifemate", unique: true);
        migrationBuilder.CreateIndex("ix_audit_logs_actor_user_id", "audit_logs", "actor_user_id", "lifemate");
        migrationBuilder.CreateIndex("ix_audit_logs_created_at_utc", "audit_logs", "created_at_utc", "lifemate");
        migrationBuilder.CreateIndex("ix_audit_logs_resource_type_resource_id", "audit_logs", new[] { "resource_type", "resource_id" }, "lifemate");
        migrationBuilder.CreateIndex("ix_privacy_consents_user_id_document_type_document_version", "privacy_consents", new[] { "user_id", "document_type", "document_version" }, "lifemate");
        migrationBuilder.CreateIndex("ix_user_profiles_email", "user_profiles", "email", "lifemate");
        migrationBuilder.CreateIndex("ix_user_profiles_phone_number", "user_profiles", "phone_number", "lifemate");
        migrationBuilder.CreateIndex("ix_user_profiles_user_id", "user_profiles", "user_id", "lifemate", unique: true);
    }
    protected override void Down(MigrationBuilder migrationBuilder)
    { migrationBuilder.DropTable("audit_logs", "lifemate"); migrationBuilder.DropTable("privacy_consents", "lifemate"); migrationBuilder.DropTable("user_profiles", "lifemate"); migrationBuilder.DropTable("app_users", "lifemate"); }
}

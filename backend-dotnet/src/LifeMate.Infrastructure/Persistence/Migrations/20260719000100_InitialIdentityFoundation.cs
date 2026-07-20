using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace LifeMate.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class InitialIdentityFoundation : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.EnsureSchema(
                name: "lifemate");

            migrationBuilder.CreateTable(
                name: "app_users",
                schema: "lifemate",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    auth_subject = table.Column<string>(type: "character varying(256)", maxLength: 256, nullable: false),
                    status = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: false),
                    created_at_utc = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    updated_at_utc = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_app_users", x => x.id);
                });

            migrationBuilder.CreateTable(
                name: "audit_logs",
                schema: "lifemate",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    actor_user_id = table.Column<Guid>(type: "uuid", nullable: true),
                    action = table.Column<string>(type: "character varying(128)", maxLength: 128, nullable: false),
                    resource_type = table.Column<string>(type: "character varying(128)", maxLength: 128, nullable: false),
                    resource_id = table.Column<Guid>(type: "uuid", nullable: true),
                    metadata_json = table.Column<string>(type: "jsonb", nullable: true),
                    created_at_utc = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_audit_logs", x => x.id);
                    table.ForeignKey(
                        name: "FK_audit_logs_app_users_actor_user_id",
                        column: x => x.actor_user_id,
                        principalSchema: "lifemate",
                        principalTable: "app_users",
                        principalColumn: "id",
                        onDelete: ReferentialAction.SetNull);
                });

            migrationBuilder.CreateTable(
                name: "privacy_consents",
                schema: "lifemate",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    user_id = table.Column<Guid>(type: "uuid", nullable: false),
                    document_type = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: false),
                    document_version = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false),
                    granted_at_utc = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    revoked_at_utc = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    created_at_utc = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_privacy_consents", x => x.id);
                    table.ForeignKey(
                        name: "FK_privacy_consents_app_users_user_id",
                        column: x => x.user_id,
                        principalSchema: "lifemate",
                        principalTable: "app_users",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "user_profiles",
                schema: "lifemate",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    user_id = table.Column<Guid>(type: "uuid", nullable: false),
                    display_name = table.Column<string>(type: "character varying(120)", maxLength: 120, nullable: false),
                    phone_number = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: true),
                    email = table.Column<string>(type: "character varying(320)", maxLength: 320, nullable: true),
                    locale = table.Column<string>(type: "character varying(16)", maxLength: 16, nullable: false, defaultValue: "fa"),
                    time_zone = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false, defaultValue: "Asia/Tehran"),
                    created_at_utc = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    updated_at_utc = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_user_profiles", x => x.id);
                    table.ForeignKey(
                        name: "FK_user_profiles_app_users_user_id",
                        column: x => x.user_id,
                        principalSchema: "lifemate",
                        principalTable: "app_users",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateIndex(
                name: "IX_app_users_auth_subject",
                schema: "lifemate",
                table: "app_users",
                column: "auth_subject",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_audit_logs_actor_user_id",
                schema: "lifemate",
                table: "audit_logs",
                column: "actor_user_id");

            migrationBuilder.CreateIndex(
                name: "IX_audit_logs_created_at_utc",
                schema: "lifemate",
                table: "audit_logs",
                column: "created_at_utc");

            migrationBuilder.CreateIndex(
                name: "IX_audit_logs_resource_type_resource_id",
                schema: "lifemate",
                table: "audit_logs",
                columns: new[] { "resource_type", "resource_id" });

            migrationBuilder.CreateIndex(
                name: "IX_privacy_consents_user_id_document_type_document_version",
                schema: "lifemate",
                table: "privacy_consents",
                columns: new[] { "user_id", "document_type", "document_version" });

            migrationBuilder.CreateIndex(
                name: "IX_user_profiles_email",
                schema: "lifemate",
                table: "user_profiles",
                column: "email");

            migrationBuilder.CreateIndex(
                name: "IX_user_profiles_phone_number",
                schema: "lifemate",
                table: "user_profiles",
                column: "phone_number");

            migrationBuilder.CreateIndex(
                name: "IX_user_profiles_user_id",
                schema: "lifemate",
                table: "user_profiles",
                column: "user_id",
                unique: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "audit_logs",
                schema: "lifemate");

            migrationBuilder.DropTable(
                name: "privacy_consents",
                schema: "lifemate");

            migrationBuilder.DropTable(
                name: "user_profiles",
                schema: "lifemate");

            migrationBuilder.DropTable(
                name: "app_users",
                schema: "lifemate");
        }
    }
}

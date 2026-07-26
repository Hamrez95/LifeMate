using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace LifeMate.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class AddCareRelationships : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.RenameColumn(
                name: "id",
                schema: "lifemate",
                table: "privacy_consents",
                newName: "Id");

            migrationBuilder.RenameColumn(
                name: "id",
                schema: "lifemate",
                table: "audit_logs",
                newName: "Id");

            migrationBuilder.CreateTable(
                name: "care_invitations",
                schema: "lifemate",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    inviter_user_id = table.Column<Guid>(type: "uuid", nullable: false),
                    contact_hash = table.Column<string>(type: "character varying(128)", maxLength: 128, nullable: false),
                    token_hash = table.Column<string>(type: "character varying(128)", maxLength: 128, nullable: false),
                    status = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: false),
                    expires_at_utc = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    accepted_at_utc = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    revoked_at_utc = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    created_at_utc = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_care_invitations", x => x.Id);
                    table.ForeignKey(
                        name: "FK_care_invitations_app_users_inviter_user_id",
                        column: x => x.inviter_user_id,
                        principalSchema: "lifemate",
                        principalTable: "app_users",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "care_relationships",
                schema: "lifemate",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    patient_user_id = table.Column<Guid>(type: "uuid", nullable: false),
                    caregiver_user_id = table.Column<Guid>(type: "uuid", nullable: false),
                    status = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: false),
                    consented_at_utc = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    revoked_at_utc = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    created_at_utc = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    updated_at_utc = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_care_relationships", x => x.Id);
                    table.ForeignKey(
                        name: "FK_care_relationships_app_users_caregiver_user_id",
                        column: x => x.caregiver_user_id,
                        principalSchema: "lifemate",
                        principalTable: "app_users",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_care_relationships_app_users_patient_user_id",
                        column: x => x.patient_user_id,
                        principalSchema: "lifemate",
                        principalTable: "app_users",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateIndex(
                name: "IX_care_invitations_inviter_user_id_contact_hash_status",
                schema: "lifemate",
                table: "care_invitations",
                columns: new[] { "inviter_user_id", "contact_hash", "status" });

            migrationBuilder.CreateIndex(
                name: "IX_care_invitations_token_hash",
                schema: "lifemate",
                table: "care_invitations",
                column: "token_hash",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_care_relationships_caregiver_user_id",
                schema: "lifemate",
                table: "care_relationships",
                column: "caregiver_user_id");

            migrationBuilder.CreateIndex(
                name: "IX_care_relationships_patient_user_id_caregiver_user_id_status",
                schema: "lifemate",
                table: "care_relationships",
                columns: new[] { "patient_user_id", "caregiver_user_id", "status" },
                unique: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "care_invitations",
                schema: "lifemate");

            migrationBuilder.DropTable(
                name: "care_relationships",
                schema: "lifemate");

            migrationBuilder.RenameColumn(
                name: "Id",
                schema: "lifemate",
                table: "privacy_consents",
                newName: "id");

            migrationBuilder.RenameColumn(
                name: "Id",
                schema: "lifemate",
                table: "audit_logs",
                newName: "id");
        }
    }
}

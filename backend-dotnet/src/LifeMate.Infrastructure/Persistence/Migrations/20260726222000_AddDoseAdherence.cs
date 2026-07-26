using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace LifeMate.Infrastructure.Persistence.Migrations
{
    public partial class AddDoseAdherence : Migration
    {
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "dose_occurrences",
                schema: "lifemate",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    patient_user_id = table.Column<Guid>(type: "uuid", nullable: false),
                    treatment_plan_id = table.Column<Guid>(type: "uuid", nullable: false),
                    treatment_schedule_id = table.Column<Guid>(type: "uuid", nullable: false),
                    scheduled_at_utc = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    scheduled_local_date = table.Column<DateOnly>(type: "date", nullable: false),
                    scheduled_local_time = table.Column<TimeOnly>(type: "time without time zone", nullable: false),
                    time_zone = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false),
                    status = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: false),
                    responded_at_utc = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    version = table.Column<int>(type: "integer", nullable: false),
                    created_at_utc = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    updated_at_utc = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_dose_occurrences", x => x.id);
                    table.CheckConstraint("CK_dose_occurrences_version_positive", "\"version\" > 0");
                    table.ForeignKey(
                        name: "FK_dose_occurrences_app_users_patient_user_id",
                        column: x => x.patient_user_id,
                        principalSchema: "lifemate",
                        principalTable: "app_users",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_dose_occurrences_treatment_plans_treatment_plan_id",
                        column: x => x.treatment_plan_id,
                        principalSchema: "lifemate",
                        principalTable: "treatment_plans",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "dose_adherence_events",
                schema: "lifemate",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    occurrence_id = table.Column<Guid>(type: "uuid", nullable: false),
                    actor_user_id = table.Column<Guid>(type: "uuid", nullable: false),
                    client_request_id = table.Column<Guid>(type: "uuid", nullable: false),
                    event_type = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: false),
                    previous_status = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: false),
                    resulting_status = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: false),
                    occurred_at_utc = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    recorded_at_utc = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_dose_adherence_events", x => x.id);
                    table.ForeignKey(
                        name: "FK_dose_adherence_events_app_users_actor_user_id",
                        column: x => x.actor_user_id,
                        principalSchema: "lifemate",
                        principalTable: "app_users",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_dose_adherence_events_dose_occurrences_occurrence_id",
                        column: x => x.occurrence_id,
                        principalSchema: "lifemate",
                        principalTable: "dose_occurrences",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "IX_dose_adherence_events_actor_user_id_client_request_id",
                schema: "lifemate",
                table: "dose_adherence_events",
                columns: new[] { "actor_user_id", "client_request_id" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_dose_adherence_events_occurrence_id_recorded_at_utc",
                schema: "lifemate",
                table: "dose_adherence_events",
                columns: new[] { "occurrence_id", "recorded_at_utc" });

            migrationBuilder.CreateIndex(
                name: "IX_dose_occurrences_patient_user_id_scheduled_local_date",
                schema: "lifemate",
                table: "dose_occurrences",
                columns: new[] { "patient_user_id", "scheduled_local_date" });

            migrationBuilder.CreateIndex(
                name: "IX_dose_occurrences_patient_user_id_status_scheduled_at_utc",
                schema: "lifemate",
                table: "dose_occurrences",
                columns: new[] { "patient_user_id", "status", "scheduled_at_utc" });

            migrationBuilder.CreateIndex(
                name: "IX_dose_occurrences_treatment_plan_id",
                schema: "lifemate",
                table: "dose_occurrences",
                column: "treatment_plan_id");

            migrationBuilder.CreateIndex(
                name: "IX_dose_occurrences_treatment_schedule_id_scheduled_at_utc",
                schema: "lifemate",
                table: "dose_occurrences",
                columns: new[] { "treatment_schedule_id", "scheduled_at_utc" },
                unique: true);
        }

        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(name: "dose_adherence_events", schema: "lifemate");
            migrationBuilder.DropTable(name: "dose_occurrences", schema: "lifemate");
        }
    }
}

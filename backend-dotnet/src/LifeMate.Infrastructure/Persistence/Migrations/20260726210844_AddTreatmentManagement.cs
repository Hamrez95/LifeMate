using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace LifeMate.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class AddTreatmentManagement : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "medications",
                schema: "lifemate",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    owner_user_id = table.Column<Guid>(type: "uuid", nullable: false),
                    name = table.Column<string>(type: "character varying(120)", maxLength: 120, nullable: false),
                    strength_text = table.Column<string>(type: "character varying(80)", maxLength: 80, nullable: true),
                    form = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: true),
                    notes = table.Column<string>(type: "character varying(500)", maxLength: 500, nullable: true),
                    version = table.Column<int>(type: "integer", nullable: false),
                    created_at_utc = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    updated_at_utc = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_medications", x => x.id);
                    table.CheckConstraint("CK_medications_version_positive", "\"version\" > 0");
                    table.ForeignKey(
                        name: "FK_medications_app_users_owner_user_id",
                        column: x => x.owner_user_id,
                        principalSchema: "lifemate",
                        principalTable: "app_users",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "treatment_plans",
                schema: "lifemate",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    patient_user_id = table.Column<Guid>(type: "uuid", nullable: false),
                    medication_id = table.Column<Guid>(type: "uuid", nullable: false),
                    dose_text = table.Column<string>(type: "character varying(80)", maxLength: 80, nullable: false),
                    instructions = table.Column<string>(type: "character varying(500)", maxLength: 500, nullable: true),
                    start_date = table.Column<DateOnly>(type: "date", nullable: false),
                    end_date = table.Column<DateOnly>(type: "date", nullable: true),
                    time_zone = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false),
                    status = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: false),
                    version = table.Column<int>(type: "integer", nullable: false),
                    created_at_utc = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    updated_at_utc = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_treatment_plans", x => x.id);
                    table.CheckConstraint("CK_treatment_plans_date_range", "\"end_date\" IS NULL OR \"end_date\" >= \"start_date\"");
                    table.CheckConstraint("CK_treatment_plans_version_positive", "\"version\" > 0");
                    table.ForeignKey(
                        name: "FK_treatment_plans_app_users_patient_user_id",
                        column: x => x.patient_user_id,
                        principalSchema: "lifemate",
                        principalTable: "app_users",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_treatment_plans_medications_medication_id",
                        column: x => x.medication_id,
                        principalSchema: "lifemate",
                        principalTable: "medications",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "treatment_schedules",
                schema: "lifemate",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    treatment_plan_id = table.Column<Guid>(type: "uuid", nullable: false),
                    day_of_week = table.Column<string>(type: "character varying(16)", maxLength: 16, nullable: false),
                    local_time = table.Column<TimeOnly>(type: "time without time zone", nullable: false),
                    created_at_utc = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_treatment_schedules", x => x.id);
                    table.ForeignKey(
                        name: "FK_treatment_schedules_treatment_plans_treatment_plan_id",
                        column: x => x.treatment_plan_id,
                        principalSchema: "lifemate",
                        principalTable: "treatment_plans",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "IX_medications_owner_user_id_name",
                schema: "lifemate",
                table: "medications",
                columns: new[] { "owner_user_id", "name" });

            migrationBuilder.CreateIndex(
                name: "IX_treatment_plans_medication_id",
                schema: "lifemate",
                table: "treatment_plans",
                column: "medication_id");

            migrationBuilder.CreateIndex(
                name: "IX_treatment_plans_patient_user_id_status",
                schema: "lifemate",
                table: "treatment_plans",
                columns: new[] { "patient_user_id", "status" });

            migrationBuilder.CreateIndex(
                name: "IX_treatment_schedules_treatment_plan_id_day_of_week_local_time",
                schema: "lifemate",
                table: "treatment_schedules",
                columns: new[] { "treatment_plan_id", "day_of_week", "local_time" },
                unique: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "treatment_schedules",
                schema: "lifemate");

            migrationBuilder.DropTable(
                name: "treatment_plans",
                schema: "lifemate");

            migrationBuilder.DropTable(
                name: "medications",
                schema: "lifemate");
        }
    }
}

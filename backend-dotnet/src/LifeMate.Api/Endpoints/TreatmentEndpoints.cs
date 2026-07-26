using System.Security.Claims;
using LifeMate.Api.Models;
using LifeMate.Application.Treatments;
using Microsoft.AspNetCore.Mvc;

namespace LifeMate.Api.Endpoints;

public static class TreatmentEndpoints
{
    public static IEndpointRouteBuilder MapTreatmentEndpoints(this IEndpointRouteBuilder app)
    {
        var medications = app.MapGroup("/api/v1/medications")
            .RequireAuthorization()
            .WithTags("Medications");
        medications.MapPost("/", CreateMedicationAsync).RequireRateLimiting("api-write");
        medications.MapGet("/", ListMedicationsAsync).DisableRateLimiting();
        medications.MapPut("/{medicationId:guid}", UpdateMedicationAsync).RequireRateLimiting("api-write");

        var plans = app.MapGroup("/api/v1/treatment-plans")
            .RequireAuthorization()
            .WithTags("Treatment plans");
        plans.MapPost("/", CreatePlanAsync).RequireRateLimiting("api-write");
        plans.MapGet("/", ListPlansAsync).DisableRateLimiting();
        plans.MapGet("/{planId:guid}", GetPlanAsync).DisableRateLimiting();
        plans.MapPut("/{planId:guid}", UpdatePlanAsync).RequireRateLimiting("api-write");
        plans.MapPost("/{planId:guid}/pause", PausePlanAsync).RequireRateLimiting("api-write");
        plans.MapPost("/{planId:guid}/resume", ResumePlanAsync).RequireRateLimiting("api-write");
        plans.MapPost("/{planId:guid}/archive", ArchivePlanAsync).RequireRateLimiting("api-write");

        return app;
    }

    private static async Task<IResult> CreateMedicationAsync(
        ClaimsPrincipal principal,
        CreateMedicationRequest request,
        TreatmentService treatments,
        CancellationToken cancellationToken)
    {
        var result = await treatments.CreateMedicationAsync(
            new CreateMedicationCommand(
                GetIdentity(principal),
                request.Name,
                request.StrengthText,
                request.Form,
                request.Notes),
            cancellationToken);
        return result.Succeeded
            ? Results.Created($"/api/v1/medications/{result.Value!.Id}", result.Value)
            : ToProblem(result);
    }

    private static async Task<IResult> ListMedicationsAsync(
        ClaimsPrincipal principal,
        TreatmentService treatments,
        CancellationToken cancellationToken)
    {
        var result = await treatments.ListMedicationsAsync(GetIdentity(principal), cancellationToken);
        return result.Succeeded ? Results.Ok(result.Value) : ToProblem(result);
    }

    private static async Task<IResult> UpdateMedicationAsync(
        ClaimsPrincipal principal,
        Guid medicationId,
        UpdateMedicationRequest request,
        TreatmentService treatments,
        CancellationToken cancellationToken)
    {
        var result = await treatments.UpdateMedicationAsync(
            new UpdateMedicationCommand(
                GetIdentity(principal),
                medicationId,
                request.Version,
                request.Name,
                request.StrengthText,
                request.Form,
                request.Notes),
            cancellationToken);
        return result.Succeeded ? Results.Ok(result.Value) : ToProblem(result);
    }

    private static async Task<IResult> CreatePlanAsync(
        ClaimsPrincipal principal,
        CreateTreatmentPlanRequest request,
        TreatmentService treatments,
        CancellationToken cancellationToken)
    {
        var result = await treatments.CreatePlanAsync(
            new CreateTreatmentPlanCommand(
                GetIdentity(principal),
                request.MedicationId,
                request.DoseText,
                request.Instructions,
                request.StartDate,
                request.EndDate,
                request.TimeZone,
                MapSchedules(request.Schedules)),
            cancellationToken);
        return result.Succeeded
            ? Results.Created($"/api/v1/treatment-plans/{result.Value!.Id}", result.Value)
            : ToProblem(result);
    }

    private static async Task<IResult> ListPlansAsync(
        ClaimsPrincipal principal,
        [FromQuery] bool includeArchived,
        TreatmentService treatments,
        CancellationToken cancellationToken)
    {
        var result = await treatments.ListPlansAsync(
            GetIdentity(principal),
            includeArchived,
            cancellationToken);
        return result.Succeeded ? Results.Ok(result.Value) : ToProblem(result);
    }

    private static async Task<IResult> GetPlanAsync(
        ClaimsPrincipal principal,
        Guid planId,
        TreatmentService treatments,
        CancellationToken cancellationToken)
    {
        var result = await treatments.GetPlanAsync(GetIdentity(principal), planId, cancellationToken);
        return result.Succeeded ? Results.Ok(result.Value) : ToProblem(result);
    }

    private static async Task<IResult> UpdatePlanAsync(
        ClaimsPrincipal principal,
        Guid planId,
        UpdateTreatmentPlanRequest request,
        TreatmentService treatments,
        CancellationToken cancellationToken)
    {
        var result = await treatments.UpdatePlanAsync(
            new UpdateTreatmentPlanCommand(
                GetIdentity(principal),
                planId,
                request.Version,
                request.MedicationId,
                request.DoseText,
                request.Instructions,
                request.StartDate,
                request.EndDate,
                request.TimeZone,
                MapSchedules(request.Schedules)),
            cancellationToken);
        return result.Succeeded ? Results.Ok(result.Value) : ToProblem(result);
    }

    private static Task<IResult> PausePlanAsync(
        ClaimsPrincipal principal,
        Guid planId,
        TreatmentPlanVersionRequest request,
        TreatmentService treatments,
        CancellationToken cancellationToken) =>
        ChangeStatusAsync(
            treatments.PausePlanAsync(
                new ChangeTreatmentPlanStatusCommand(GetIdentity(principal), planId, request.Version),
                cancellationToken));

    private static Task<IResult> ResumePlanAsync(
        ClaimsPrincipal principal,
        Guid planId,
        TreatmentPlanVersionRequest request,
        TreatmentService treatments,
        CancellationToken cancellationToken) =>
        ChangeStatusAsync(
            treatments.ResumePlanAsync(
                new ChangeTreatmentPlanStatusCommand(GetIdentity(principal), planId, request.Version),
                cancellationToken));

    private static Task<IResult> ArchivePlanAsync(
        ClaimsPrincipal principal,
        Guid planId,
        TreatmentPlanVersionRequest request,
        TreatmentService treatments,
        CancellationToken cancellationToken) =>
        ChangeStatusAsync(
            treatments.ArchivePlanAsync(
                new ChangeTreatmentPlanStatusCommand(GetIdentity(principal), planId, request.Version),
                cancellationToken));

    private static async Task<IResult> ChangeStatusAsync(Task<TreatmentResult<TreatmentPlanDto>> operation)
    {
        var result = await operation;
        return result.Succeeded ? Results.Ok(result.Value) : ToProblem(result);
    }

    private static TreatmentIdentity GetIdentity(ClaimsPrincipal principal) => new(
        principal.FindFirstValue(ClaimTypes.NameIdentifier)
            ?? principal.FindFirstValue("sub")
            ?? throw new InvalidOperationException("Authenticated JWT is missing the sub claim."));

    private static IReadOnlyCollection<TreatmentScheduleInput> MapSchedules(
        IReadOnlyCollection<TreatmentScheduleRequest>? schedules) =>
        schedules?.Select(x => new TreatmentScheduleInput(x.DayOfWeek, x.LocalTime)).ToArray()
        ?? [];

    private static IResult ToProblem<T>(TreatmentResult<T> result)
    {
        var statusCode = result.ErrorKind switch
        {
            TreatmentErrorKind.Validation => StatusCodes.Status400BadRequest,
            TreatmentErrorKind.NotFound => StatusCodes.Status404NotFound,
            TreatmentErrorKind.Conflict => StatusCodes.Status409Conflict,
            _ => StatusCodes.Status500InternalServerError
        };

        return Results.Problem(new ProblemDetails
        {
            Status = statusCode,
            Title = result.ErrorCode,
            Detail = result.ErrorMessage,
            Extensions = { ["code"] = result.ErrorCode }
        });
    }
}

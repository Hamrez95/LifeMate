using System.Security.Claims;
using LifeMate.Api.Models;
using LifeMate.Application.Adherence;
using Microsoft.AspNetCore.Mvc;

namespace LifeMate.Api.Endpoints;

public static class AdherenceEndpoints
{
    public static IEndpointRouteBuilder MapAdherenceEndpoints(this IEndpointRouteBuilder app)
    {
        var doses = app.MapGroup("/api/v1/dose-occurrences")
            .RequireAuthorization()
            .WithTags("Dose adherence");
        doses.MapGet("/", ListAsync).DisableRateLimiting();
        doses.MapPost("/{occurrenceId:guid}/report", ReportAsync)
            .RequireRateLimiting("api-write");
        return app;
    }

    private static async Task<IResult> ListAsync(
        ClaimsPrincipal principal,
        [FromQuery] DateOnly fromDate,
        [FromQuery] DateOnly toDate,
        AdherenceService adherence,
        CancellationToken cancellationToken)
    {
        var result = await adherence.ListAsync(
            new ListDoseOccurrencesCommand(GetIdentity(principal), fromDate, toDate),
            cancellationToken);
        return result.Succeeded ? Results.Ok(result.Value) : ToProblem(result);
    }

    private static async Task<IResult> ReportAsync(
        ClaimsPrincipal principal,
        Guid occurrenceId,
        ReportDoseOccurrenceRequest request,
        AdherenceService adherence,
        CancellationToken cancellationToken)
    {
        var result = await adherence.ReportAsync(
            new ReportDoseOccurrenceCommand(
                GetIdentity(principal),
                occurrenceId,
                request.ClientRequestId,
                request.Version,
                request.Status,
                request.OccurredAtUtc),
            cancellationToken);
        return result.Succeeded ? Results.Ok(result.Value) : ToProblem(result);
    }

    private static AdherenceIdentity GetIdentity(ClaimsPrincipal principal) => new(
        principal.FindFirstValue(ClaimTypes.NameIdentifier)
            ?? principal.FindFirstValue("sub")
            ?? throw new InvalidOperationException("Authenticated JWT is missing the sub claim."));

    private static IResult ToProblem<T>(AdherenceResult<T> result)
    {
        var statusCode = result.ErrorKind switch
        {
            AdherenceErrorKind.Validation => StatusCodes.Status400BadRequest,
            AdherenceErrorKind.NotFound => StatusCodes.Status404NotFound,
            AdherenceErrorKind.Conflict => StatusCodes.Status409Conflict,
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

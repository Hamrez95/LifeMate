using System.Security.Claims;
using LifeMate.Api.Models;
using LifeMate.Application.Care;
using Microsoft.AspNetCore.Mvc;

namespace LifeMate.Api.Endpoints;

public static class CareEndpoints
{
    public static RouteGroupBuilder MapCareEndpoints(this IEndpointRouteBuilder app)
    {
        var group = app.MapGroup("/api/v1/care")
            .RequireAuthorization()
            .WithTags("Care");

        group.MapPost("/invitations", CreateInvitationAsync)
            .RequireRateLimiting("api-write");
        group.MapGet("/invitations", ListInvitationsAsync)
            .DisableRateLimiting();
        group.MapPost("/invitations/accept", AcceptInvitationAsync)
            .RequireRateLimiting("api-write");
        group.MapPost("/invitations/reject", RejectInvitationAsync)
            .RequireRateLimiting("api-write");
        group.MapDelete("/invitations/{invitationId:guid}", RevokeInvitationAsync)
            .RequireRateLimiting("api-write");
        group.MapGet("/relationships", ListRelationshipsAsync)
            .DisableRateLimiting();
        group.MapDelete("/relationships/{relationshipId:guid}", RevokeRelationshipAsync)
            .RequireRateLimiting("api-write");

        return group;
    }

    private static async Task<IResult> CreateInvitationAsync(
        ClaimsPrincipal principal,
        CreateCareInvitationRequest request,
        CareService care,
        CancellationToken cancellationToken)
    {
        var result = await care.CreateInvitationAsync(
            new CreateCareInvitationCommand(
                GetIdentity(principal),
                request.ContactType,
                request.Contact,
                request.ConsentVersion,
                request.ConfirmConsent),
            cancellationToken);

        return result.Succeeded
            ? Results.Created($"/api/v1/care/invitations/{result.Value!.Id}", result.Value)
            : ToProblem(result);
    }

    private static async Task<IResult> ListInvitationsAsync(
        ClaimsPrincipal principal,
        CareService care,
        CancellationToken cancellationToken)
    {
        var result = await care.ListOutgoingInvitationsAsync(
            GetIdentity(principal),
            cancellationToken);
        return result.Succeeded ? Results.Ok(result.Value) : ToProblem(result);
    }

    private static async Task<IResult> AcceptInvitationAsync(
        ClaimsPrincipal principal,
        AcceptCareInvitationRequest request,
        CareService care,
        CancellationToken cancellationToken)
    {
        var result = await care.AcceptInvitationAsync(
            new AcceptCareInvitationCommand(
                GetIdentity(principal),
                request.Token,
                request.ConsentVersion,
                request.ConfirmConsent),
            cancellationToken);
        return result.Succeeded ? Results.Ok(result.Value) : ToProblem(result);
    }

    private static async Task<IResult> RejectInvitationAsync(
        ClaimsPrincipal principal,
        RejectCareInvitationRequest request,
        CareService care,
        CancellationToken cancellationToken)
    {
        var result = await care.RejectInvitationAsync(
            new RejectCareInvitationCommand(GetIdentity(principal), request.Token),
            cancellationToken);
        return result.Succeeded ? Results.Ok(result.Value) : ToProblem(result);
    }

    private static async Task<IResult> RevokeInvitationAsync(
        ClaimsPrincipal principal,
        Guid invitationId,
        CareService care,
        CancellationToken cancellationToken)
    {
        var result = await care.RevokeInvitationAsync(
            GetIdentity(principal),
            invitationId,
            cancellationToken);
        return result.Succeeded ? Results.Ok(result.Value) : ToProblem(result);
    }

    private static async Task<IResult> ListRelationshipsAsync(
        ClaimsPrincipal principal,
        CareService care,
        CancellationToken cancellationToken)
    {
        var result = await care.ListRelationshipsAsync(
            GetIdentity(principal),
            cancellationToken);
        return result.Succeeded ? Results.Ok(result.Value) : ToProblem(result);
    }

    private static async Task<IResult> RevokeRelationshipAsync(
        ClaimsPrincipal principal,
        Guid relationshipId,
        CareService care,
        CancellationToken cancellationToken)
    {
        var result = await care.RevokeRelationshipAsync(
            GetIdentity(principal),
            relationshipId,
            cancellationToken);
        return result.Succeeded ? Results.Ok(result.Value) : ToProblem(result);
    }

    private static AuthenticatedCareIdentity GetIdentity(ClaimsPrincipal principal)
    {
        var subject = principal.FindFirstValue(ClaimTypes.NameIdentifier)
            ?? principal.FindFirstValue("sub")
            ?? throw new InvalidOperationException("Authenticated JWT is missing the sub claim.");

        var email = principal.FindFirstValue("email")
            ?? principal.FindFirstValue(ClaimTypes.Email);
        var phone = principal.FindFirstValue("phone")
            ?? principal.FindFirstValue("phone_number")
            ?? principal.FindFirstValue(ClaimTypes.MobilePhone);

        return new AuthenticatedCareIdentity(subject, email, phone);
    }

    private static IResult ToProblem<T>(CareResult<T> result)
    {
        var statusCode = result.ErrorKind switch
        {
            CareErrorKind.Validation => StatusCodes.Status400BadRequest,
            CareErrorKind.NotFound => StatusCodes.Status404NotFound,
            CareErrorKind.Forbidden => StatusCodes.Status403Forbidden,
            CareErrorKind.Conflict => StatusCodes.Status409Conflict,
            CareErrorKind.Gone => StatusCodes.Status410Gone,
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

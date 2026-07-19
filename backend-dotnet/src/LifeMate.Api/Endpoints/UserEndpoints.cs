using System.Security.Claims;
using LifeMate.Api.Models;
using LifeMate.Application.Users;
using Microsoft.AspNetCore.Http.HttpResults;
using Microsoft.AspNetCore.Mvc;

namespace LifeMate.Api.Endpoints;

public static class UserEndpoints
{
    public static RouteGroupBuilder MapUserEndpoints(this IEndpointRouteBuilder app)
    {
        var group = app.MapGroup("/api/v1").RequireAuthorization().RequireRateLimiting("api-write");
        group.MapPost("/users/bootstrap", BootstrapAsync);
        group.MapGet("/me", GetMeAsync).DisableRateLimiting();
        group.MapPut("/me/profile", UpdateProfileAsync);
        return group;
    }
    private static async Task<Results<Ok<CurrentUserDto>, ValidationProblem>> BootstrapAsync(ClaimsPrincipal principal, BootstrapUserRequest request, UserService users, CancellationToken ct)
    {
        var errors = ValidateBootstrap(request);
        if (errors.Count > 0) return TypedResults.ValidationProblem(errors);
        var result = await users.BootstrapAsync(new BootstrapUserCommand(GetSubject(principal), request.DisplayName, request.PhoneNumber, request.Email, request.Locale, request.TimeZone), ct);
        return TypedResults.Ok(result);
    }
    private static async Task<Results<Ok<CurrentUserDto>, NotFound<ProblemDetails>>> GetMeAsync(ClaimsPrincipal principal, UserService users, CancellationToken ct)
    {
        var result = await users.GetMeAsync(GetSubject(principal), ct);
        return result.Succeeded ? TypedResults.Ok(result.Value!) : TypedResults.NotFound(new ProblemDetails { Title = "User is not onboarded", Detail = result.ErrorMessage, Extensions = { ["code"] = result.ErrorCode } });
    }
    private static async Task<Results<Ok<CurrentUserDto>, NotFound<ProblemDetails>, ValidationProblem>> UpdateProfileAsync(ClaimsPrincipal principal, UpdateProfileRequest request, UserService users, CancellationToken ct)
    {
        var errors = ValidateProfile(request);
        if (errors.Count > 0) return TypedResults.ValidationProblem(errors);
        var result = await users.UpdateProfileAsync(new UpdateProfileCommand(GetSubject(principal), request.DisplayName, request.Locale, request.TimeZone, request.PhoneNumber, request.Email), ct);
        if (result.Succeeded) return TypedResults.Ok(result.Value!);
        if (result.ErrorCode == "invalid_profile") return TypedResults.ValidationProblem(new Dictionary<string, string[]> { ["profile"] = [result.ErrorMessage ?? "Invalid profile."] });
        return TypedResults.NotFound(new ProblemDetails { Title = "User is not onboarded", Detail = result.ErrorMessage, Extensions = { ["code"] = result.ErrorCode } });
    }
    private static Dictionary<string, string[]> ValidateBootstrap(BootstrapUserRequest request)
    {
        var errors = new Dictionary<string, string[]>();
        if (!string.IsNullOrWhiteSpace(request.Email) && !request.Email.Contains('@', StringComparison.Ordinal)) errors["email"] = ["Email is invalid."];
        if (request.DisplayName?.Length > 120) errors["displayName"] = ["Display name must be 120 characters or fewer."];
        return errors;
    }
    private static Dictionary<string, string[]> ValidateProfile(UpdateProfileRequest request)
    {
        var errors = new Dictionary<string, string[]>();
        if (string.IsNullOrWhiteSpace(request.DisplayName)) errors["displayName"] = ["Display name is required."];
        if (!string.IsNullOrWhiteSpace(request.Email) && !request.Email.Contains('@', StringComparison.Ordinal)) errors["email"] = ["Email is invalid."];
        return errors;
    }
    private static string GetSubject(ClaimsPrincipal principal) => principal.FindFirstValue(ClaimTypes.NameIdentifier) ?? principal.FindFirstValue("sub") ?? throw new InvalidOperationException("Authenticated JWT is missing the sub claim.");
}

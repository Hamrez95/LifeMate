# LifeMate Repository Instructions

## Repository structure
- `wellmate/`: Flutter patient app.
- `caremate/`: Flutter caregiver app.
- `backend/`: temporary Dart/Shelf demo backend. Do not delete it yet.
- `backend-dotnet/`: production ASP.NET Core modular monolith backend.

## Safe commands
- Backend restore: `dotnet restore backend-dotnet/LifeMate.sln`
- Backend build: `dotnet build backend-dotnet/LifeMate.sln --no-restore`
- Backend tests: `dotnet test backend-dotnet/LifeMate.sln --no-build`
- Local database: `docker compose -f backend-dotnet/docker-compose.yml up -d postgres`

## Rules
- Never commit secrets, production connection strings, service-role keys, JWTs, refresh tokens, OTP codes, or passwords.
- Use environment variables or standard ASP.NET Core configuration for production settings.
- Never modify generated EF Core migrations manually after review; create a follow-up migration instead.
- Use one focused branch and pull request per feature.
- The existing Dart backend is temporary and must not be deleted yet.
- Flutter apps must access core product data through `LifeMate.Api`; they must not directly read or mutate healthcare tables.

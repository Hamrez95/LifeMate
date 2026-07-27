FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src

COPY Directory.Build.props LifeMate.sln ./
COPY src/LifeMate.Domain/LifeMate.Domain.csproj src/LifeMate.Domain/
COPY src/LifeMate.Application/LifeMate.Application.csproj src/LifeMate.Application/
COPY src/LifeMate.Infrastructure/LifeMate.Infrastructure.csproj src/LifeMate.Infrastructure/
COPY src/LifeMate.Api/LifeMate.Api.csproj src/LifeMate.Api/
RUN dotnet restore src/LifeMate.Api/LifeMate.Api.csproj

COPY src/ src/
RUN dotnet publish src/LifeMate.Api/LifeMate.Api.csproj \
    --configuration Release \
    --no-restore \
    --output /app/publish \
    /p:UseAppHost=false

FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS runtime
WORKDIR /app
ENV ASPNETCORE_HTTP_PORTS=8080
EXPOSE 8080

COPY --from=build /app/publish .
USER $APP_UID
ENTRYPOINT ["dotnet", "LifeMate.Api.dll"]

FROM mcr.microsoft.com/dotnet/sdk:8.0-windowsservercore-ltsc2022 AS build-env
WORKDIR /app
COPY . ./
RUN dotnet publish asp_frontend_service/asp_frontend_service.csproj -c Release -o out

FROM mcr.microsoft.com/dotnet/aspnet:8.0-windowsservercore-ltsc2022
WORKDIR /app
EXPOSE 8080
COPY --from=build-env /app/out .
ENTRYPOINT ["dotnet", "asp_frontend_service.dll"]
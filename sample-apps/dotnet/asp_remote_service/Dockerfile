ARG DOTNET_VERSION=8.0
FROM mcr.microsoft.com/dotnet/sdk:${DOTNET_VERSION} AS build-env
WORKDIR /app
COPY . ./
RUN dotnet publish asp_remote_service/*.csproj -c Release -o out

FROM mcr.microsoft.com/dotnet/aspnet:${DOTNET_VERSION}-noble-chiseled
WORKDIR /app
ENV ASPNETCORE_URLS=http://+:8081
EXPOSE 8081
COPY --from=build-env /app/out .
ENTRYPOINT ["dotnet", "asp_remote_service.dll"]

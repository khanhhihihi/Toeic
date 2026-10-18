FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build

WORKDIR /src
COPY ["src/ToeicApp.Web.Host/ToeicApp.Web.Host.csproj", "src/ToeicApp.Web.Host/"]
COPY ["src/ToeicApp.Web.Core/ToeicApp.Web.Core.csproj", "src/ToeicApp.Web.Core/"]
COPY ["src/ToeicApp.Application/ToeicApp.Application.csproj", "src/ToeicApp.Application/"]
COPY ["src/ToeicApp.Core/ToeicApp.Core.csproj", "src/ToeicApp.Core/"]
COPY ["src/ToeicApp.EntityFrameworkCore/ToeicApp.EntityFrameworkCore.csproj", "src/ToeicApp.EntityFrameworkCore/"]
WORKDIR "/src/src/ToeicApp.Web.Host"
RUN dotnet restore 

WORKDIR /src
COPY ["src/ToeicApp.Web.Host", "src/ToeicApp.Web.Host"]
COPY ["src/ToeicApp.Web.Core", "src/ToeicApp.Web.Core"]
COPY ["src/ToeicApp.Application", "src/ToeicApp.Application"]
COPY ["src/ToeicApp.Core", "src/ToeicApp.Core"]
COPY ["src/ToeicApp.EntityFrameworkCore", "src/ToeicApp.EntityFrameworkCore"]
WORKDIR "/src/src/ToeicApp.Web.Host"
RUN dotnet publish -c Release -o /publish --no-restore

FROM mcr.microsoft.com/dotnet/aspnet:8.0
EXPOSE 80
WORKDIR /app
COPY --from=build /publish .
ENTRYPOINT ["dotnet", "ToeicApp.Web.Host.dll"]

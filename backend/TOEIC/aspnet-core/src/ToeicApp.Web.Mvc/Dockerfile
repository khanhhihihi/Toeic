FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build

RUN dotnet tool install -g Microsoft.Web.LibraryManager.Cli
RUN ln -s ~/.dotnet/tools/libman /usr/local/bin/libman

WORKDIR /src
COPY ["src/ToeicApp.Web.Mvc/ToeicApp.Web.Mvc.csproj", "src/ToeicApp.Web.Mvc/"]
COPY ["src/ToeicApp.Web.Core/ToeicApp.Web.Core.csproj", "src/ToeicApp.Web.Core/"]
COPY ["src/ToeicApp.Application/ToeicApp.Application.csproj", "src/ToeicApp.Application/"]
COPY ["src/ToeicApp.Core/ToeicApp.Core.csproj", "src/ToeicApp.Core/"]
COPY ["src/ToeicApp.EntityFrameworkCore/ToeicApp.EntityFrameworkCore.csproj", "src/ToeicApp.EntityFrameworkCore/"]
WORKDIR "/src/src/ToeicApp.Web.Mvc"
RUN dotnet restore 

WORKDIR /src
COPY ["src/ToeicApp.Web.Mvc", "src/ToeicApp.Web.Mvc"]
COPY ["src/ToeicApp.Web.Core", "src/ToeicApp.Web.Core"]
COPY ["src/ToeicApp.Application", "src/ToeicApp.Application"]
COPY ["src/ToeicApp.Core", "src/ToeicApp.Core"]
COPY ["src/ToeicApp.EntityFrameworkCore", "src/ToeicApp.EntityFrameworkCore"]
WORKDIR "/src/src/ToeicApp.Web.Mvc"
RUN libman restore
RUN dotnet publish -c Release -o /publish --no-restore

FROM mcr.microsoft.com/dotnet/aspnet:8.0
EXPOSE 80
WORKDIR /app
COPY --from=build /publish .
ENTRYPOINT ["dotnet", "ToeicApp.Web.Mvc.dll"]

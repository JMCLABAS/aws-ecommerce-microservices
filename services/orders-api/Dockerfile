# --- ETAPA 1: Construcción (Build) ---
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src

# Copiamos el archivo de proyecto .csproj y restauramos dependencias
COPY ["OrdersApi.csproj", "./"]
RUN dotnet restore "OrdersApi.csproj"

# Copiamos todo lo demás y construimos
COPY . .
RUN dotnet build "OrdersApi.csproj" -c Release -o /app/build

# Publicamos la aplicación (prepara los archivos finales)
FROM build AS publish
RUN dotnet publish "OrdersApi.csproj" -c Release -o /app/publish

# --- ETAPA 2: Ejecución (Runtime) ---
FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS final
WORKDIR /app
EXPOSE 80
EXPOSE 443

# Copiamos los archivos publicados desde la etapa anterior
COPY --from=publish /app/publish .

# Punto de entrada
ENTRYPOINT ["dotnet", "OrdersApi.dll"]
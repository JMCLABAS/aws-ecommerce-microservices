# --- Etapa 1: Build Stage (SDK) ---
# Se utiliza la imagen completa del SDK de .NET 8.0 para el entorno de compilación.
# Esta capa incluye todas las herramientas de CLI (dotnet) necesarias para el CI/CD.
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src

# Optimización de Caché de Capas (Layer Caching).
# Se copia primero el archivo de definición del proyecto (.csproj) y se restauran los paquetes NuGet.
# Esto permite que Docker cachee las dependencias externas si no hay cambios en el .csproj,
# reduciendo drásticamente los tiempos de compilación en builds subsiguientes.
COPY ["OrdersApi.csproj", "./"]
RUN dotnet restore "OrdersApi.csproj"

# Inyección del código fuente y compilación.
# Se compila en configuración 'Release' para asegurar que el compilador JIT aplique
# las optimizaciones de rendimiento necesarias para producción.
COPY . .
RUN dotnet build "OrdersApi.csproj" -c Release -o /app/build

# Generación de Artefactos de Despliegue.
# La etapa de publicación empaqueta la aplicación y sus dependencias, eliminando 
# archivos temporales y preparando la estructura de directorios final.
FROM build AS publish
RUN dotnet publish "OrdersApi.csproj" -c Release -o /app/publish

# --- Etapa 2: Runtime Stage (Production) ---
# Se cambia a la imagen base de ASP.NET Core Runtime (sin SDK).
# Esto reduce significativamente el tamaño de la imagen final y minimiza la superficie de ataque
# al eliminar herramientas de compilación no necesarias en ejecución.
FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS final
WORKDIR /app
EXPOSE 80
EXPOSE 443

# Estrategia Multi-Stage Build.
# Transferencia exclusiva de los binarios compilados y optimizados desde la etapa 'publish',
# garantizando un contenedor limpio y ligero (Lightweight Container).
COPY --from=publish /app/publish .

# Definición del Entrypoint del contenedor.
# Ejecuta la aplicación como proceso principal (PID 1) gestionando el ciclo de vida del servicio.
ENTRYPOINT ["dotnet", "OrdersApi.dll"]
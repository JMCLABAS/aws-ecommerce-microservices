using OrdersApi.Controllers;

var builder = WebApplication.CreateBuilder(args);

// --- Configuración del Contenedor de Inversión de Control (IoC) ---

// Registro de servicios del framework necesarios para la arquitectura basada en Controladores.
// Esto habilita la inyección de dependencias en los constructores de los Controllers.
builder.Services.AddControllers();

// Integración de herramientas de descubrimiento de endpoints y generación de especificación OpenAPI.
// Esencial para garantizar que el contrato de la API sea visible y consumible por servicios externos.
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

var app = builder.Build();

// --- Definición del Pipeline de Middleware de Procesamiento de Peticiones ---

// Habilitación del middleware de documentación y la interfaz Swagger UI.
// Se configura de forma agnóstica al entorno (Environment-Agnostic) para permitir 
// la introspección y validación de contratos directamente sobre el contenedor Docker desplegado.
app.UseSwagger();
app.UseSwaggerUI();

app.UseAuthorization();

// Mapeo de rutas de los controladores al pipeline de ejecución.
// Asocia los endpoints definidos en los Controllers con las peticiones HTTP entrantes.
app.MapControllers();

app.Run();
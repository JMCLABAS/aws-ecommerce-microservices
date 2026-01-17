using OrdersApi.Controllers;

var builder = WebApplication.CreateBuilder(args);

// --- 1. Configuración de Servicios (Dependency Injection) ---

// Añadimos soporte para Controladores
builder.Services.AddControllers();

// Añadimos Swagger/OpenAPI (Estilo .NET 8)
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

var app = builder.Build();

// --- 2. Configuración del Pipeline HTTP ---

// Configuramos Swagger para poder probar la API visualmente
// (Permitimos que se vea incluso fuera de entorno 'Development' para que lo veas en Docker)
app.UseSwagger();
app.UseSwaggerUI();

app.UseAuthorization();

// Mapeamos los controladores
app.MapControllers();

app.Run();
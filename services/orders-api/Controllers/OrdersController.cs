using Microsoft.AspNetCore.Mvc;
using OrdersApi.Models;

namespace OrdersApi.Controllers;

[ApiController]
[Route("[controller]")] // La ruta será /orders
public class OrdersController : ControllerBase
{
    // Simulamos una base de datos en memoria (static mantiene los datos mientras la app corre)
    private static readonly List<Order> _orders = new()
    {
        new Order { Id = 1, CustomerName = "Test User", TotalAmount = 150.00m }
    };

    private readonly ILogger<OrdersController> _logger;

    public OrdersController(ILogger<OrdersController> logger)
    {
        _logger = logger;
    }

    [HttpGet]
    public IEnumerable<Order> Get()
    {
        return _orders;
    }

    [HttpPost]
    public IActionResult Create(Order order)
    {
        order.Id = _orders.Count + 1;
        order.CreatedAt = DateTime.UtcNow;
        _orders.Add(order);
        
        return CreatedAtAction(nameof(Get), new { id = order.Id }, order);
    }
}
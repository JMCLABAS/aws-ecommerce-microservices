package main

import (
	"encoding/json"
	"log"
	"net/http"
)

// Product representa el DTO (Data Transfer Object) del dominio de catálogo.
// Se definen 'struct tags' para asegurar el contrato de serialización JSON
// esperado por los servicios consumidores (Frontend/Mobile).
type Product struct {
	ID    string  `json:"id"`
	Name  string  `json:"name"`
	Price float64 `json:"price"`
}

func main() {
	// Definición del endpoint RESTful.
	// Se utiliza el DefaultServeMux para enrutar peticiones HTTP.
	// En un entorno productivo, esto podría sustituirse por un router como Chi o Gin
	// para manejar middlewares y parámetros de ruta de forma más eficiente.
	http.HandleFunc("/products", func(w http.ResponseWriter, r *http.Request) {

		// Simulación de la capa de persistencia (Mock Data).
		// En producción, esto invocaría a un repositorio que consulta una base de datos
		// (PostgreSQL/MongoDB) o una caché distribuida (Redis) para reducir latencia.
		products := []Product{
			{ID: "1", Name: "Laptop Gamer AWS", Price: 1500.00},
			{ID: "2", Name: "Mouse Dockerizado", Price: 25.50},
			{ID: "3", Name: "Teclado Mecánico Kubernetes", Price: 80.00},
		}

		// Establecimiento de cabeceras para la Negociación de Contenido.
		// Indica explícitamente al cliente que el payload es JSON estricto.
		w.Header().Set("Content-Type", "application/json")

		// Serialización eficiente mediante Streams.
		// Se prefiere json.NewEncoder(w).Encode() sobre json.Marshal() para escribir
		// directamente en el io.Writer, optimizando el uso de memoria (evita buffers intermedios).
		json.NewEncoder(w).Encode(products)
	})

	log.Println("Catalog Service running on :8080")

	// Inicio del servidor HTTP en modo bloqueante.
	// Escucha en el puerto 8080 para orquestación dentro de contenedores (Docker/K8s).
	if err := http.ListenAndServe(":8080", nil); err != nil {
		log.Fatal(err)
	}
}

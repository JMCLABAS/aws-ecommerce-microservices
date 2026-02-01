# --- Etapa 1: Build Stage ---
# Se utiliza la imagen base de Golang sobre Alpine para asegurar un entorno de compilación ligero
# pero con todas las herramientas necesarias para el toolchain de Go.
FROM golang:1.22-alpine AS builder

WORKDIR /app

# Optimización de Caché de Capas (Layer Caching).
# Copiamos primero las definiciones de módulos. Esto permite a Docker cachear
# la capa de descarga de dependencias si 'go.mod' no ha cambiado, 
# acelerando significativamente los tiempos de construcción en CI/CD.
COPY go.mod ./
# COPY go.sum ./ # Se descomentaría si existiera para verificar la integridad de checksums.
RUN go mod download

# Copia del código fuente al contexto de construcción.
COPY . .

# Compilación del artefacto.
# Se genera un binario estático apuntando al entrypoint de la aplicación.
# En producción, se podrían añadir flags como -ldflags="-s -w" para eliminar símbolos de depuración y reducir tamaño.
RUN go build -o main ./cmd/api

# --- Etapa 2: Runtime Stage ---
# Se utiliza una imagen Alpine limpia para el entorno de ejecución final.
# Estrategia 'Distroless' o minimalista para reducir la superficie de ataque y el tamaño de la imagen final.
FROM alpine:latest

WORKDIR /root/

# Transferencia de Artefactos.
# Se copia EXCLUSIVAMENTE el binario compilado desde la etapa 'builder',
# descartando el código fuente, caché de módulos y herramientas de compilación (Go CLI).
COPY --from=builder /app/main .

# Documentación del puerto de servicio para orquestadores de contenedores.
EXPOSE 8080

# Definición del proceso principal del contenedor.
CMD ["./main"]
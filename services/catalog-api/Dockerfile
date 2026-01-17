# --- ETAPA 1: Construcción (Builder) ---
FROM golang:1.22-alpine AS builder

WORKDIR /app

# Copiamos los archivos de dependencias primero (para aprovechar el caché de Docker)
COPY go.mod ./
# Si tuvieras go.sum, lo copiarías aquí también: COPY go.sum ./
RUN go mod download

# Copiamos el resto del código
COPY . .

# Compilamos el binario. 
# -o main: nombre del ejecutable
# ./cmd/api: ruta donde está tu main.go
RUN go build -o main ./cmd/api

# --- ETAPA 2: Ejecución (Runner) ---
FROM alpine:latest

WORKDIR /root/

# Copiamos SOLO el binario compilado desde la etapa anterior
COPY --from=builder /app/main .

# Exponemos el puerto (informativo)
EXPOSE 8080

# Comando para ejecutar la app
CMD ["./main"]
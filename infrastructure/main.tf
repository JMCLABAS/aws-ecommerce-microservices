terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }


  backend "s3" {
    bucket = "terraform-state-ecommerce-pepe" # <--- ¡PON TU NOMBRE DE BUCKET AQUÍ!
    key    = "global/s3/terraform.tfstate"
    region = "eu-west-1"
  }

}

# Aquí le decimos a Terraform que use tus credenciales de AWS CLI automáticamente
provider "aws" {
  region = "eu-west-1"  # Importante: Que coincida con la región que pusiste en 'aws configure'
}

# --- 1. VPC (Virtual Private Cloud) ---
resource "aws_vpc" "main_vpc" {
  cidr_block           = "10.0.0.0/16" # Esto nos da 65,536 direcciones IP privadas
  enable_dns_support   = true          # Para tener nombres de dominio internos
  enable_dns_hostnames = true          # Para que las instancias tengan nombre DNS

  tags = {
    Name = "ecommerce-vpc"
  }
}

# --- 2. Subnets Públicas ---

# Subnet 1 (En la Zona A)
resource "aws_subnet" "public_subnet_1" {
  vpc_id                  = aws_vpc.main_vpc.id  # La conectamos a la VPC de arriba
  cidr_block              = "10.0.1.0/24"        # IPs tipo 10.0.1.X
  availability_zone       = "eu-west-1a"         # Zona física 1
  map_public_ip_on_launch = true                 # Asigna IP pública automática (útil para pruebas)

  tags = {
    Name = "ecommerce-public-subnet-1"
  }
}

# Subnet 2 (En la Zona B - Alta Disponibilidad)
resource "aws_subnet" "public_subnet_2" {
  vpc_id                  = aws_vpc.main_vpc.id
  cidr_block              = "10.0.2.0/24"        # IPs tipo 10.0.2.X
  availability_zone       = "eu-west-1b"         # Zona física 2
  map_public_ip_on_launch = true

  tags = {
    Name = "ecommerce-public-subnet-2"
  }
}

# --- 3. Internet Gateway (La puerta a internet) ---
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main_vpc.id

  tags = {
    Name = "ecommerce-igw"
  }
}

# --- 4. Route Table (El mapa de carreteras) ---
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main_vpc.id

  route {
    cidr_block = "0.0.0.0/0"                 # Significa: "Para ir a cualquier sitio (internet)..."
    gateway_id = aws_internet_gateway.igw.id # "...sal por la puerta principal (IGW)"
  }

  tags = {
    Name = "ecommerce-public-rt"
  }
}

# --- 5. Asociaciones (Entregar el mapa a las subredes) ---
# Le damos el mapa a la Subnet 1
resource "aws_route_table_association" "public_assoc_1" {
  subnet_id      = aws_subnet.public_subnet_1.id
  route_table_id = aws_route_table.public_rt.id
}

# Le damos el mapa a la Subnet 2
resource "aws_route_table_association" "public_assoc_2" {
  subnet_id      = aws_subnet.public_subnet_2.id
  route_table_id = aws_route_table.public_rt.id
}

# --- 6. Security Group (El Portero / Firewall) ---
resource "aws_security_group" "app_sg" {
  name        = "ecommerce-app-sg"
  description = "Permitir trafico web a los microservicios"
  vpc_id      = aws_vpc.main_vpc.id

  # Regla de entrada: Permitir tráfico en puerto 8080 (Go - Catalog) desde cualquier sitio
  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Regla de entrada: Permitir tráfico en puerto 5000 (NET - Orders) desde cualquier sitio
  ingress {
    from_port   = 5000 # Ojo: .NET 8 suele usar 8080 o 5000, abrimos ambos por si acaso
    to_port     = 5000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Regla de entrada: Permitir tráfico HTTP estándar (Puerto 80)
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Regla de salida: Permitir a los servidores salir a internet (para actualizaciones, etc)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1" # -1 significa "todos los protocolos"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "ecommerce-sg"
  }
}

# --- 7. ECR Repositories (El Garaje de Imágenes) ---
resource "aws_ecr_repository" "catalog_repo" {
  name         = "catalog-api"
  force_delete = true # Permite borrar el repo aunque tenga imágenes dentro (útil para pruebas)
}

resource "aws_ecr_repository" "orders_repo" {
  name         = "orders-api"
  force_delete = true
}

# --- 8. ECS Cluster (El Motor que coordina todo) ---
resource "aws_ecs_cluster" "main_cluster" {
  name = "ecommerce-cluster"

  tags = {
    Name = "ecommerce-cluster"
  }
}

# --- 9. IAM Role (Permisos para que ECS pueda descargar imágenes y escribir logs) ---
resource "aws_iam_role" "ecs_execution_role" {
  name = "ecommerce-ecs-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
    }]
  })
}

# Le pegamos el permiso oficial de Amazon para ejecutar tareas ECS
resource "aws_iam_role_policy_attachment" "ecs_execution_role_policy" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# --- 10. CloudWatch Logs (Para ver qué pasa dentro de tus apps) ---
resource "aws_cloudwatch_log_group" "catalog_logs" {
  name              = "/ecs/catalog-api"
  retention_in_days = 7
}

resource "aws_cloudwatch_log_group" "orders_logs" {
  name              = "/ecs/orders-api"
  retention_in_days = 7
}

# ==========================================
# MICROSERVICIO 1: CATALOG API (Go)
# ==========================================

# 1. La Receta (Task Definition)
resource "aws_ecs_task_definition" "catalog_task" {
  family                   = "catalog-api-task"
  network_mode             = "awsvpc" # Modo de red obligatorio para Fargate
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"    # 0.25 vCPU (Lo mínimo para gastar poco)
  memory                   = "512"    # 512 MB RAM

  execution_role_arn = aws_iam_role.ecs_execution_role.arn

  container_definitions = jsonencode([{
    name  = "catalog-api"
    image = "${aws_ecr_repository.catalog_repo.repository_url}:latest" # Terraform busca la URL por ti
    portMappings = [{
      containerPort = 8080
      hostPort      = 8080
    }]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = "/ecs/catalog-api"
        "awslogs-region"        = "eu-west-1"
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])
}

# 2. El Servicio (Service) - El que ejecuta la receta
resource "aws_ecs_service" "catalog_service" {
  name            = "catalog-api-service"
  cluster         = aws_ecs_cluster.main_cluster.id
  task_definition = aws_ecs_task_definition.catalog_task.arn
  launch_type     = "FARGATE"
  desired_count   = 1 # Queremos 1 copia funcionando

  network_configuration {
    subnets          = [aws_subnet.public_subnet_1.id, aws_subnet.public_subnet_2.id]
    security_groups  = [aws_security_group.app_sg.id]
    assign_public_ip = true # Importante para que pueda descargar la imagen de internet
  }
}

# ==========================================
# MICROSERVICIO 2: ORDERS API (.NET)
# ==========================================

# 3. La Receta
resource "aws_ecs_task_definition" "orders_task" {
  family                   = "orders-api-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn

  container_definitions = jsonencode([{
    name  = "orders-api"
    image = "${aws_ecr_repository.orders_repo.repository_url}:latest"
    portMappings = [{
      containerPort = 8080 # .NET 8 escucha en 8080 por defecto también
      hostPort      = 8080
    }]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = "/ecs/orders-api"
        "awslogs-region"        = "eu-west-1"
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])
}

# 4. El Servicio
resource "aws_ecs_service" "orders_service" {
  name            = "orders-api-service"
  cluster         = aws_ecs_cluster.main_cluster.id
  task_definition = aws_ecs_task_definition.orders_task.arn
  launch_type     = "FARGATE"
  desired_count   = 1

  network_configuration {
    subnets          = [aws_subnet.public_subnet_1.id, aws_subnet.public_subnet_2.id]
    security_groups  = [aws_security_group.app_sg.id]
    assign_public_ip = true
  }
}

resource "aws_sqs_queue" "cola_prueba" {
  name                      = "mi-primera-cola-terraform"
  delay_seconds             = 90
  max_message_size          = 2048
  message_retention_seconds = 86400
  receive_wait_time_seconds = 10
}
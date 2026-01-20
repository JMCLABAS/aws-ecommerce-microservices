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

resource "aws_sqs_queue" "ecommerce_orders" { # Nombre interno de Terraform cambiado
  name                      = "ecommerce-orders-queue" # Nombre real en AWS cambiado
  delay_seconds             = 0
  max_message_size          = 2048
  message_retention_seconds = 86400
  receive_wait_time_seconds = 10
  
  tags = {
    Environment = "Production"
    Project     = "E-commerce Core"
  }
}


# 1. Crear el Bucket para la web
resource "aws_s3_bucket" "web_bucket" {
  bucket = "mi-web-ecommerce-portfolio-jmclabas" 
  
  tags = {
    Name        = "Static Website Bucket"
    Environment = "Production"
  }
}

# 2. Configurar el bucket para que funcione como sitio web
resource "aws_s3_bucket_website_configuration" "web_config" {
  bucket = aws_s3_bucket.web_bucket.id

  index_document {
    suffix = "index.html"
  }
}

# 3. Desbloquear el acceso público (necesario para ver la web)
resource "aws_s3_bucket_public_access_block" "web_public_access" {
  bucket = aws_s3_bucket.web_bucket.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

# 4. Política de seguridad: Permitir que CUALQUIERA lea los archivos (Read Only)
resource "aws_s3_bucket_policy" "web_policy" {
  bucket = aws_s3_bucket.web_bucket.id
  depends_on = [aws_s3_bucket_public_access_block.web_public_access]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.web_bucket.arn}/*"
      },
    ]
  })
}

resource "aws_s3_object" "index_file" {
  bucket       = aws_s3_bucket.web_bucket.id
  key          = "index.html"
  content_type = "text/html; charset=utf-8"

  content = <<EOF
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <title>E-commerce Infrastructure</title>
    <style>
        body { font-family: 'Segoe UI', sans-serif; text-align: center; padding: 50px; background-color: #f8f9fa; }
        .container { background: white; padding: 40px; border-radius: 12px; box-shadow: 0 10px 25px rgba(0,0,0,0.1); max-width: 600px; margin: auto; }
        button { background-color: #007bff; color: white; border: none; padding: 15px 30px; border-radius: 50px; font-size: 1.2em; cursor: pointer; transition: 0.3s; box-shadow: 0 4px 6px rgba(0,123,255,0.3); }
        button:hover { background-color: #0056b3; transform: translateY(-2px); }
        .status { margin-top: 20px; font-weight: bold; color: #28a745; min-height: 24px;}
        .resource-list { text-align: left; margin-top: 30px; border-top: 1px solid #eee; padding-top: 20px; color: #6c757d; }
    </style>
    <script>
        async function comprar() {
            const btn = document.getElementById('btnComprar');
            const status = document.getElementById('statusMsg');
            
            btn.disabled = true;
            btn.innerText = "Procesando...";
            status.innerText = "";

            try {
                // Terraform inyecta aquí la URL de la Lambda automáticamente:
                const response = await fetch("${aws_lambda_function_url.lambda_url.function_url}", {
                    method: 'POST',
                    headers: {'Content-Type': 'application/json'}
                });
                
                const data = await response.json();
                status.innerText = "✅ " + data.message + " (ID: " + data.id + ")";
                status.style.color = "#28a745";
            } catch (error) {
                status.innerText = "❌ Error al conectar con el Backend";
                status.style.color = "red";
                console.error(error);
            } finally {
                btn.disabled = false;
                btn.innerText = "Simular Compra 🛒";
            }
        }
    </script>
</head>
<body>
    <div class="container">
        <h1>Tienda Serverless Demo</h1>
        <p>Prueba de concepto de arquitectura de 3 capas.</p>
        
        <div style="margin: 40px 0;">
            <button id="btnComprar" onclick="comprar()">Simular Compra 🛒</button>
            <div id="statusMsg" class="status"></div>
        </div>

        <div class="resource-list">
            <p><strong>Arquitectura Activa:</strong></p>
            <ul>
                <li>🌐 Frontend (S3)</li>
                <li>⚡ API (Lambda Function URL)</li>
                <li>💾 Database (DynamoDB)</li>
            </ul>
        </div>
    </div>
</body>
</html>
EOF
}

# 6. OUTPUT: Para que GitHub nos diga la URL al terminar
output "website_url" {
  value = aws_s3_bucket_website_configuration.web_config.website_endpoint
  description = "La URL de mi página web estática"
}

# 7. Base de Datos DynamoDB para el Inventario
resource "aws_dynamodb_table" "inventory_table" {
  name           = "ecommerce-inventory-prod"
  billing_mode   = "PAY_PER_REQUEST" # Serverless (solo pagas por uso, o sea, gratis ahora)
  hash_key       = "ProductId"
  
  attribute {
    name = "ProductId"
    type = "S" # String
  }

  tags = {
    Environment = "Production"
    Name        = "InventoryTable"
  }
}

# --- INICIO BLOQUE LAMBDA ---

# 1. Empaquetar el archivo Python para subirlo
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "lambda_function.py"
  output_path = "lambda_function.zip"
}

# 2. Crear un Rol de IAM para que la Lambda pueda actuar
resource "aws_iam_role" "lambda_role" {
  name = "ecommerce_lambda_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

# 3. Dar permiso a la Lambda para escribir en DynamoDB y guardar logs
resource "aws_iam_role_policy" "lambda_policy" {
  name = "ecommerce_lambda_policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow",
        Action = ["dynamodb:PutItem", "dynamodb:Scan"],
        Resource = aws_dynamodb_table.inventory_table.arn
      },
      {
        Effect = "Allow",
        Action = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"],
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# 4. Crear la Función Lambda
resource "aws_lambda_function" "backend_lambda" {
  filename         = "lambda_function.zip"
  function_name    = "ecommerce-backend-function"
  role             = aws_iam_role.lambda_role.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.9"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  
  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.inventory_table.name
    }
  }
}

# 5. Crear una URL pública para invocar la Lambda (Function URL)
resource "aws_lambda_function_url" "lambda_url" {
  function_name      = aws_lambda_function.backend_lambda.function_name
  authorization_type = "NONE"
  
  cors {
    allow_credentials = true
    allow_origins     = ["*"]
    allow_methods     = ["*"]
    allow_headers     = ["date", "keep-alive", "content-type"]
    expose_headers    = ["keep-alive", "date"]
    max_age           = 86400
  }
}

# 6. Permiso explícito para que CUALQUIERA pueda invocar la URL
resource "aws_lambda_permission" "allow_public_access" {
  statement_id           = "FunctionURLAllowPublicAccess_v2"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.backend_lambda.function_name
  principal              = "*"
  function_url_auth_type = "NONE"
}
# --- FIN BLOQUE LAMBDA ---
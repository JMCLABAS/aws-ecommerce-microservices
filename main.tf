terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4.2"
    }
  }
  
  # Configuración del Backend remoto para la persistencia del Estado (Terraform State).
  # S3 garantiza la durabilidad del estado y permite la colaboración en equipo,
  # mientras que DynamoDB (si se configurara) gestionaría el bloqueo para evitar condiciones de carrera.
  backend "s3" {
    bucket = "terraform-state-ecommerce-pepe" 
    key    = "global/s3/terraform.tfstate"     
    region = "eu-west-1"
  }
}

provider "aws" {
  region = "eu-west-1"
}

# -----------------------------------------------------------
# 1. CAPA DE DATOS (Persistencia NoSQL)
# -----------------------------------------------------------
resource "aws_dynamodb_table" "inventory_table" {
  name           = "ecommerce-inventory-prod"
  
  # Se utiliza el modelo 'On-Demand' para optimizar costes (OpEx) eliminando
  # la necesidad de aprovisionar capacidad de lectura/escritura (RCU/WCU) ociosa.
  billing_mode   = "PAY_PER_REQUEST" 
  hash_key       = "ProductId"

  attribute {
    name = "ProductId"
    type = "S"
  }

  tags = {
    Environment = "Production"
    Project     = "ServerlessShop"
  }
}

# -----------------------------------------------------------
# 2. CAPA DE LÓGICA DE NEGOCIO (Compute / Serverless)
# -----------------------------------------------------------

# Generación del artefacto de despliegue mediante compresión en tiempo de ejecución.
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "lambda_function.py"
  output_path = "lambda_function.zip"
}

# Definición de Roles IAM (Identity and Access Management).
# Permite a la función Lambda asumir credenciales temporales de seguridad
# para interactuar con otros servicios de AWS.
resource "aws_iam_role" "lambda_role" {
  name = "ecommerce_lambda_role_final_v3"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

# Implementación del Principio de Mínimo Privilegio (PoLP).
# Se otorgan permisos granulares explícitos (PutItem, Scan) únicamente
# sobre la tabla de inventario, restringiendo el radio de impacto ante posibles brechas.
resource "aws_iam_role_policy" "lambda_policy" {
  name = "ecommerce_lambda_policy_final_v3"
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
        # Permisos necesarios para la observabilidad y trazabilidad en CloudWatch Logs.
        Effect = "Allow",
        Action = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"],
        Resource = "arn:aws:logs:*:*:*" 
      }
    ]
  })
}

# Definición del recurso computacional.
# Se inyectan las variables de entorno necesarias para desacoplar la configuración
# del código fuente, siguiendo la metodología '12-Factor App'.
resource "aws_lambda_function" "backend_lambda" {
  filename         = "lambda_function.zip"
  function_name    = "ecommerce-backend-function"
  role             = aws_iam_role.lambda_role.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.12" # Runtime actualizado para soporte a largo plazo (LTS)
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
 
  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.inventory_table.name
    }
  }
}

# Exposición pública mediante Function URLs.
# Simplifica la arquitectura al eliminar la sobrecarga de gestión de un API Gateway completo,
# reduciendo la latencia y los costes operativos para este microservicio.
resource "aws_lambda_function_url" "lambda_url" {
  function_name      = aws_lambda_function.backend_lambda.function_name
  authorization_type = "NONE"
  
  # Configuración de Cross-Origin Resource Sharing (CORS).
  # Habilita la comunicación segura entre el Frontend (S3) y el Backend (Lambda)
  # permitiendo verbos HTTP y cabeceras específicas.
  cors {
    allow_credentials = false
    allow_origins     = ["*"]
    allow_methods     = ["*"]                 
    allow_headers     = ["date", "keep-alive", "content-type"]
    expose_headers    = ["keep-alive", "date"]
    max_age           = 86400
  }
}

# Política basada en recursos para permitir la invocación pública de la URL de la función.
resource "aws_lambda_permission" "allow_public_access" {
  statement_id           = "AllowPublicAccess_FinalClean_v6" 
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.backend_lambda.function_name
  principal              = "*"
  function_url_auth_type = "NONE"
}

# -----------------------------------------------------------
# 3. CAPA DE PRESENTACIÓN (Frontend Estático)
# -----------------------------------------------------------
resource "aws_s3_bucket" "web_bucket" {
  bucket = "mi-web-ecommerce-portfolio-jmclabas"
}

# Configuración del bucket para alojamiento web estático.
# Transforma el almacenamiento de objetos en un servidor web básico.
resource "aws_s3_bucket_website_configuration" "web_config" {
  bucket = aws_s3_bucket.web_bucket.id
  index_document { suffix = "index.html" }
}

# Gestión de acceso público.
# Se deshabilitan los bloqueos por defecto para permitir que el bucket sirva
# contenido web públicamente a través de Internet.
resource "aws_s3_bucket_public_access_block" "web_public_access" {
  bucket = aws_s3_bucket.web_bucket.id
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

# Política de bucket (Bucket Policy).
# Define permisos de solo lectura (s3:GetObject) para cualquier usuario anónimo,
# permitiendo la visualización del sitio web.
resource "aws_s3_bucket_policy" "web_policy" {
  bucket = aws_s3_bucket.web_bucket.id
  depends_on = [aws_s3_bucket_public_access_block.web_public_access]
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "PublicReadGetObject"
      Effect    = "Allow"
      Principal = "*"
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.web_bucket.arn}/*"
    }]
  })
}

# Despliegue del artefacto Frontend (Single Page Application).
# Se inyecta la URL del backend dinámicamente utilizando interpolación de Terraform.
resource "aws_s3_object" "index_file" {
  bucket       = aws_s3_bucket.web_bucket.id
  key          = "index.html"
  content_type = "text/html; charset=utf-8"

  content = <<EOF
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>CloudShop Demo</title>
    <style>
        :root { --primary: #2563eb; --bg: #f3f4f6; --text: #1f2937; }
        body { font-family: 'Segoe UI', system-ui, sans-serif; background-color: var(--bg); color: var(--text); margin: 0; padding: 20px; }
        .header { text-align: center; margin-bottom: 40px; }
        .header h1 { color: var(--primary); font-size: 2.5rem; margin-bottom: 10px; }
        .badge { background: #dbeafe; color: #1e40af; padding: 5px 12px; border-radius: 20px; font-weight: bold; font-size: 0.9rem; }
        .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(280px, 1fr)); gap: 30px; max-width: 1000px; margin: 0 auto; }
        .card { background: white; border-radius: 16px; overflow: hidden; box-shadow: 0 4px 6px rgba(0,0,0,0.05); transition: transform 0.2s; }
        .card:hover { transform: translateY(-5px); box-shadow: 0 10px 15px rgba(0,0,0,0.1); }
        .card img { width: 100%; height: 200px; object-fit: cover; }
        .card-body { padding: 20px; }
        .card h3 { margin: 0 0 10px 0; }
        .price { font-size: 1.5rem; font-weight: bold; color: var(--primary); display: block; margin-bottom: 15px; }
        button { width: 100%; background: var(--primary); color: white; border: none; padding: 12px; border-radius: 8px; font-weight: bold; cursor: pointer; transition: background 0.2s; }
        button:hover { background: #1d4ed8; }
        button:disabled { background: #9ca3af; cursor: not-allowed; }
        .toast { visibility: hidden; min-width: 250px; background-color: #333; color: #fff; text-align: center; border-radius: 8px; padding: 16px; position: fixed; z-index: 1; left: 50%; bottom: 30px; transform: translateX(-50%); font-size: 17px; }
        .toast.show { visibility: visible; animation: fadein 0.5s, fadeout 0.5s 2.5s; }
        .toast.success { background-color: #10b981; }
        .toast.error { background-color: #ef4444; }
        @keyframes fadein { from {bottom: 0; opacity: 0;} to {bottom: 30px; opacity: 1;} }
        @keyframes fadeout { from {bottom: 30px; opacity: 1;} to {bottom: 0; opacity: 0;} }
        .footer { text-align: center; margin-top: 50px; color: #6b7280; font-size: 0.9rem; }
    </style>
</head>
<body>
    <div class="header">
        <h1>🛍️ CloudShop Serverless</h1>
        <span class="badge">Architecture: S3 + Lambda + DynamoDB</span>
    </div>

    <div class="grid">
        <div class="card">
            <img src="https://images.unsplash.com/photo-1496181133206-80ce9b88a853?w=500&auto=format&fit=crop&q=60" alt="Laptop">
            <div class="card-body">
                <h3>MacBook Pro Dev</h3>
                <p>Perfecto para compilar tu código Terraform.</p>
                <span class="price">1.299 €</span>
                <button onclick="comprar('MacBook Pro Dev', 1299)">Comprar Ahora</button>
            </div>
        </div>
        <div class="card">
            <img src="https://images.unsplash.com/photo-1505740420928-5e560c06d30e?w=500&auto=format&fit=crop&q=60" alt="Auriculares">
            <div class="card-body">
                <h3>Sony WH-1000XM5</h3>
                <p>Cancelación de ruido para concentrarte.</p>
                <span class="price">349 €</span>
                <button onclick="comprar('Auriculares Sony', 349)">Comprar Ahora</button>
            </div>
        </div>
        <div class="card">
            <img src="https://images.unsplash.com/photo-1546435770-a3e426bf472b?w=500&auto=format&fit=crop&q=60" alt="Auriculares">
            <div class="card-body">
                <h3>Auriculares Cloud</h3>
                <p>Escucha tus logs con claridad cristalina.</p>
                <span class="price">89 €</span>
                <button onclick="comprar('Auriculares Cloud', 89)">Comprar Ahora</button>
            </div>
        </div>
    </div>

    <div class="footer">
        <p>Powered by AWS Lambda (Python 3.12) & GitHub Actions</p>
        <p>By: Jose María Clavijo Basáñez</p>
    </div>

    <div id="toast" class="toast">Pedido realizado...</div>

    <script>
        async function comprar(producto, precio) {
            const toast = document.getElementById("toast");
            toast.className = "toast"; 
            toast.innerText = "Procesando " + producto + "...";
            toast.classList.add("show");

            try {
                // Invocación asíncrona al Backend Serverless
                const response = await fetch("${aws_lambda_function_url.lambda_url.function_url}", {
                    method: 'POST',
                    headers: {'Content-Type': 'application/json'},
                    body: JSON.stringify({
                        product_name: producto,
                        price: precio
                    })
                });
                
                const data = await response.json();
                
                if (response.ok) {
                    toast.innerText = "✅ " + data.message;
                    toast.classList.add("success");
                } else {
                    throw new Error(data.message || "Error desconocido");
                }
            } catch (error) {
                toast.innerText = "❌ Error: " + error.message;
                toast.classList.add("error");
                console.error(error);
            }
            setTimeout(function(){ toast.className = toast.className.replace("show", ""); }, 3000);
        }
    </script>
</body>
</html>
EOF
}

output "website_url" {
  description = "Endpoint público para acceder a la aplicación web desplegada"
  value       = aws_s3_bucket_website_configuration.web_config.website_endpoint
}
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
  
  backend "s3" {
    bucket = "terraform-state-ecommerce-pepe" 
    key    = "global/s3/terraform.tfstate"    
    region = "eu-west-1"
  }
}

provider "aws" {
  region = "eu-west-1"
}

# ---------------------------------------------------------
# 1. BASE DE DATOS (DynamoDB)
# ---------------------------------------------------------
resource "aws_dynamodb_table" "inventory_table" {
  name           = "ecommerce-inventory-prod"
  billing_mode   = "PAY_PER_REQUEST" # Gratis (Capa gratuita)
  hash_key       = "ProductId"

  attribute {
    name = "ProductId"
    type = "S"
  }

  tags = {
    Environment = "Production"
  }
}

# ---------------------------------------------------------
# 2. BACKEND SERVERLESS (Lambda)
# ---------------------------------------------------------

# Empaquetar el código Python automáticamente
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "lambda_function.py"
  output_path = "lambda_function.zip"
}

# Rol de seguridad (IAM) para la Lambda
resource "aws_iam_role" "lambda_role" {
  name = "ecommerce_lambda_role_final" # Nombre único

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

# Permisos: Escribir en DynamoDB y guardar Logs
resource "aws_iam_role_policy" "lambda_policy" {
  name = "ecommerce_lambda_policy_final"
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

# La Función Lambda 
resource "aws_lambda_function" "backend_lambda" {
  filename         = "lambda_function.zip"
  function_name    = "ecommerce-backend-function"
  role             = aws_iam_role.lambda_role.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.12"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  
  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.inventory_table.name
    }
  }
}

# URL Pública de la Lambda (API Gateway simplificado)
resource "aws_lambda_function_url" "lambda_url" {
  function_name      = aws_lambda_function.backend_lambda.function_name
  authorization_type = "NONE"
  
  cors {
    allow_credentials = true
    allow_origins     = ["*"]
    allow_methods     = ["*"]
    allow_headers     = ["date", "keep-alive", "content-type"] # Importante para que no de error CORS
    expose_headers    = ["keep-alive", "date"]
    max_age           = 86400
  }
}

# Permiso para que la URL sea realmente pública (El "Portero")
resource "aws_lambda_permission" "allow_public_access" {
  statement_id           = "AllowPublicAccess_FinalClean" # ID nuevo para evitar conflictos previos
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.backend_lambda.function_name
  principal              = "*"
  function_url_auth_type = "NONE"
}

# ---------------------------------------------------------
# 3. FRONTEND (S3 Website)
# ---------------------------------------------------------
resource "aws_s3_bucket" "web_bucket" {
  bucket = "mi-web-ecommerce-portfolio-jmclabas" # Tu bucket de la web
}

resource "aws_s3_bucket_website_configuration" "web_config" {
  bucket = aws_s3_bucket.web_bucket.id
  index_document { suffix = "index.html" }
}

resource "aws_s3_bucket_public_access_block" "web_public_access" {
  bucket = aws_s3_bucket.web_bucket.id
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

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

# Archivo HTML (Con la conexión automática a la Lambda)
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
        .status { margin-top: 20px; font-weight: bold; min-height: 24px;}
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
                // Terraform inyecta la URL de la Lambda aquí:
                const response = await fetch("${aws_lambda_function_url.lambda_url.function_url}", {
                    method: 'POST',
                    headers: {'Content-Type': 'application/json'}
                });
                
                const data = await response.json();
                
                if (response.ok) {
                    status.innerText = "✅ " + data.message + " (ID: " + data.id + ")";
                    status.style.color = "#28a745";
                } else {
                    throw new Error(data.message || "Error desconocido");
                }
            } catch (error) {
                status.innerText = "❌ Error: " + error.message;
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
        <h1>🚀 Tienda Serverless Demo</h1>
        <p>Prueba de concepto de arquitectura de 3 capas.</p>
        
        <div style="margin: 40px 0;">
            <button id="btnComprar" onclick="comprar()">Simular Compra 🛒</button>
            <div id="statusMsg" class="status"></div>
        </div>

        <div class="resource-list">
            <p><strong>Arquitectura Activa (Coste $0):</strong></p>
            <ul>
                <li>🌐 Frontend (S3) -> Tu navegador</li>
                <li>⚡ API (Lambda Function URL) -> Procesa la lógica</li>
                <li>💾 Database (DynamoDB) -> Guarda el pedido</li>
            </ul>
        </div>
    </div>
</body>
</html>
EOF
}

output "website_url" {
  value = aws_s3_bucket_website_configuration.web_config.website_endpoint
}
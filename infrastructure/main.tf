terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Aquí le decimos a Terraform que use tus credenciales de AWS CLI automáticamente
provider "aws" {
  region = "eu-west-1"  # Importante: Que coincida con la región que pusiste en 'aws configure'
}

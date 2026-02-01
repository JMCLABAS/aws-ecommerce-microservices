import json
import boto3
import uuid
import os
from datetime import datetime
from decimal import Decimal

def lambda_handler(event, context):
    try:
        # Inicialización del cliente SDK (Boto3) y recuperación de configuración dinámica.
        # Se utilizan variables de entorno para desacoplar la lógica de negocio de la infraestructura,
        # siguiendo la metodología "12-Factor App".
        dynamodb = boto3.resource('dynamodb')
        table_name = os.environ.get('TABLE_NAME')
        table = dynamodb.Table(table_name)
        
        # Deserialización del payload y validación de entrada.
        # Se extrae el cuerpo de la petición HTTP proxy (API Gateway/Function URL).
        body = {}
        if event.get('body'):
            body = json.loads(event.get('body'))
            
        product_name = body.get('product_name', 'Producto Desconocido')
        price = body.get('price', 0)
        
        # Generación de metadatos de trazabilidad.
        # Se utiliza UUIDv4 para garantizar unicidad global en sistemas distribuidos
        # y formato ISO 8601 para estandarización temporal.
        order_id = str(uuid.uuid4())
        timestamp = datetime.now().isoformat()
        
        # Persistencia en capa de datos NoSQL.
        # Conversión explícita a tipo Decimal para evitar errores de precisión de punto flotante
        # inherentes al manejo de datos monetarios en DynamoDB.
        table.put_item(
            Item={
                'ProductId': order_id,
                'Tipo': 'Pedido Web',
                'Producto': product_name,
                'Precio': Decimal(str(price)),
                'Fecha': timestamp,
                'Estado': 'Confirmado'
            }
        )
        
        # Construcción de respuesta estandarizada según el contrato de API Gateway.
        # Retorna código 200 OK y estructura JSON para el cliente.
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json'},
            'body': json.dumps({
                'message': f'¡Compraste {product_name}!', 
                'id': order_id
            })
        }
        
    except Exception as e:
        # Manejo global de excepciones para asegurar degradación elegante.
        # El error se registra en CloudWatch Logs para observabilidad y depuración.
        print(f"ERROR: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json'},
            'body': json.dumps({'message': f'Error: {str(e)}'})
        }
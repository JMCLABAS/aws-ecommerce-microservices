import json
import boto3
import uuid
import os
from datetime import datetime

# Inicializamos el recurso fuera del handler para mejor rendimiento
dynamodb = boto3.resource('dynamodb')

def lambda_handler(event, context):
    try:
        # 1. Obtenemos el nombre de la tabla desde la variable de entorno (inyectada por Terraform)
        # Esto evita errores si cambiamos el nombre de la tabla en el futuro.
        table_name = os.environ.get('TABLE_NAME')
        table = dynamodb.Table(table_name)
        
        # 2. Generamos datos del pedido
        order_id = str(uuid.uuid4())
        timestamp = datetime.now().isoformat()
        
        # 3. Guardamos en DynamoDB
        table.put_item(
            Item={
                'ProductId': order_id,
                'Tipo': 'Pedido Simulado',
                'Fecha': timestamp,
                'Estado': 'Procesado'
            }
        )
        
        return {
            'statusCode': 200,
            'headers': {
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Methods': 'POST, GET, OPTIONS',
                'Access-Control-Allow-Headers': 'content-type'
            },
            'body': json.dumps({'message': 'Pedido Exitoso', 'id': order_id})
        }
        
    except Exception as e:
        # Si algo falla, devolvemos el error exacto para verlo en la web
        print(f"Error: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Methods': 'POST, GET, OPTIONS',
                'Access-Control-Allow-Headers': 'content-type'
            },
            'body': json.dumps({'message': f'Error Interno: {str(e)}', 'id': 'ERROR'})
        }
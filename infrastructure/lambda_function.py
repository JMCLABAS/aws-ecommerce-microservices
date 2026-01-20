import json
import boto3
import uuid
from datetime import datetime

dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table('ecommerce-inventory-prod')

def lambda_handler(event, context):
    # Generamos un ID de pedido único y una fecha
    order_id = str(uuid.uuid4())
    timestamp = datetime.now().isoformat()
    
    # Guardamos el item en DynamoDB
    table.put_item(
        Item={
            'ProductId': order_id, # Usamos el ID de orden como clave
            'Tipo': 'Pedido Simulado',
            'Fecha': timestamp,
            'Estado': 'Procesado'
        }
    )
    
    # Respondemos al navegador (con cabeceras CORS para que no falle)
    return {
        'statusCode': 200,
        'headers': {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'POST, GET, OPTIONS',
            'Access-Control-Allow-Headers': 'Content-Type'
        },
        'body': json.dumps({'message': 'Pedido realizado con exito!', 'id': order_id})
    }
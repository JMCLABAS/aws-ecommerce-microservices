import json
import boto3
import uuid
import os
from datetime import datetime
from decimal import Decimal

def lambda_handler(event, context):
    try:
        # 1. Configurar DynamoDB
        dynamodb = boto3.resource('dynamodb')
        table_name = os.environ.get('TABLE_NAME')
        table = dynamodb.Table(table_name)
        
        # 2. Leer los datos que vienen de la web
        body = {}
        if event.get('body'):
            body = json.loads(event.get('body'))
            
        product_name = body.get('product_name', 'Producto Desconocido')
        price = body.get('price', 0)
        
        # 3. Generar datos del pedido
        order_id = str(uuid.uuid4())
        timestamp = datetime.now().isoformat()
        
        # 4. Guardar en DynamoDB (Convertimos precio a Decimal)
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
        
        # 5. Responder
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
        print(f"ERROR: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json'},
            'body': json.dumps({'message': f'Error: {str(e)}'})
        }
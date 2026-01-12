import json
import boto3
import os
import urllib.request
from datetime import datetime

def lambda_handler(event, context):
    s3 = boto3.client('s3')
    bucket_name = os.environ['BUCKET_NAME']
    api_key = os.environ['API_KEY']
    
    # Exemplo: Clima de São Paulo
    lat, lon = "-23.5505", "-46.6333"
    url = f"https://api.openweathermap.org/data/2.5/weather?lat={lat}&lon={lon}&appid={api_key}&units=metric"
    
    try:
        with urllib.request.urlopen(url) as response:
            data = json.loads(response.read().decode())
        
        # Estrutura de pastas: datalake/bronze/YYYY-MM-DD/
        date_str = datetime.now().strftime("%Y-%m-%d")
        file_name = f"datalake/bronze/{date_str}/weather_{datetime.now().timestamp()}.json"
        
        s3.put_object(
            Bucket=bucket_name,
            Key=file_name,
            Body=json.dumps(data)
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps(f'Sucesso! Arquivo salvo em {file_name}')
        }
    except Exception as e:
        print(e)
        raise e
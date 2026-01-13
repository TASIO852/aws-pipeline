import sys
import boto3
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from pyspark.sql.functions import col, current_date, avg

# Recebendo argumentos do Glue/Terraform
args = getResolvedOptions(sys.argv, [
    'JOB_NAME', 
    'BUCKET_NAME', 
    'DB_USER', 
    'DB_PASSWORD', 
    'DB_NAME', 
    'REDSHIFT_WORKGROUP',
    'aws_region'
])

sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args['JOB_NAME'], args)

bucket_name = args['BUCKET_NAME']

# --- 1. CAMADA SILVER (Limpeza e Padronização) ---
# Ler JSON da Bronze
bronze_path = f"s3://{bucket_name}/datalake/bronze/*/*"
df_bronze = spark.read.json(bronze_path)

# Transformação: Selecionar colunas, renomear e remover duplicados
df_silver = df_bronze.select(
    col("name").alias("cidade"),
    col("main.temp").alias("temperatura"),
    col("main.humidity").alias("umidade"),
    col("weather")[0]["description"].alias("condicao"),
    current_date().alias("data_processamento")
).dropDuplicates()

# Salvar na Silver em Parquet
silver_path = f"s3://{bucket_name}/datalake/silver/"
df_silver.write.mode("overwrite").parquet(silver_path)

# --- 2. CAMADA GOLD (Agregação) ---
# Cálculo de médias climáticas
df_gold = df_silver.groupBy("cidade", "data_processamento") \
    .agg(
        avg("temperatura").alias("temp_media"), 
        avg("umidade").alias("umidade_media")
    )

# Salvar na Gold em Parquet antes da carga
gold_path = f"s3://{bucket_name}/datalake/gold/"
df_gold.write.mode("overwrite").parquet(gold_path)

# --- 3. CARGA PARA REDSHIFT (Via Data API & COPY) ---
print("Iniciando carga no Redshift via Data API...")

# Definição das variáveis de ambiente para a carga
cluster_id = args['REDSHIFT_WORKGROUP']
db_name = args['DB_NAME']
s3_path_gold = gold_path
# ATENÇÃO: Verifique se este ARN de Role está correto conforme seu iam.tf
iam_role_arn = f"arn:aws:iam::{boto3.client('sts').get_caller_identity()['Account']}:role/desafio-agrin-redshift-role"

# SQL de DDL e DML (Criação e Carga)
# O comando COPY é mais eficiente que o JDBC para grandes volumes
sql_command = f"""
CREATE TABLE IF NOT EXISTS public.clima_diario_gold (
    cidade VARCHAR(100),
    data_processamento DATE,
    temp_media FLOAT,
    umidade_media FLOAT
);
COPY public.clima_diario_gold 
FROM '{s3_path_gold}' 
IAM_ROLE '{iam_role_arn}' 
FORMAT AS PARQUET;
"""

# Inicializa o cliente da Data API
client_redshift = boto3.client('redshift-data', region_name=args['aws_region'])

try:
    # Executa o comando SQL de forma assíncrona
    response = client_redshift.execute_statement(
        WorkgroupName=cluster_id,
        Database=db_name,
        Sql=sql_command
    )
    print(f"Comando COPY enviado com sucesso! Query ID: {response['Id']}")
except Exception as e:
    print(f"Erro ao executar carga no Redshift: {str(e)}")
    raise e

job.commit()
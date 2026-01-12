import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from pyspark.sql.functions import col, current_date, avg

args = getResolvedOptions(sys.argv, ['JOB_NAME', 'BUCKET_NAME', 'DB_USER', 'DB_PASSWORD', 'DB_NAME', 'REDSHIFT_WORKGROUP'])

sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args['JOB_NAME'], args)

bucket_name = args['BUCKET_NAME']

# --- CAMADA SILVER (Limpeza e Padronização) ---
# Ler JSON da Bronze
bronze_path = f"s3://{bucket_name}/datalake/bronze/*/*"
df_bronze = spark.read.json(bronze_path)

# Transformação simples: Selecionar colunas, renomear e adicionar data de processamento
df_silver = df_bronze.select(
    col("name").alias("cidade"),
    col("main.temp").alias("temperatura"),
    col("main.humidity").alias("umidade"),
    col("weather")[0]["description"].alias("condicao"),
    current_date().alias("data_processamento")
).dropDuplicates()

# Escrever na Silver (Parquet) [cite: 15]
silver_path = f"s3://{bucket_name}/datalake/silver/"
df_silver.write.mode("overwrite").parquet(silver_path)

# --- CAMADA GOLD (Agregação para Redshift) ---
# Exemplo de agregação: Média de temperatura por cidade
df_gold = df_silver.groupBy("cidade", "data_processamento") \
    .agg(avg("temperatura").alias("temp_media"), avg("umidade").alias("umidade_media"))

# Escrever no Redshift Serverless (JDBC)
# Nota: Em um ambiente real, deve-se configurar a conexão JDBC no Glue Connection ou Secrets Manager
# Este é um exemplo simplificado de escrita direta via conector Spark-Redshift
jdbc_url = f"jdbc:redshift://{args['REDSHIFT_WORKGROUP']}.{args['aws_region']}.redshift-serverless.amazonaws.com:5439/{args['DB_NAME']}"

df_gold.write \
    .format("jdbc") \
    .option("url", jdbc_url) \
    .option("dbtable", "public.clima_diario_gold") \
    .option("user", args['DB_USER']) \
    .option("password", args['DB_PASSWORD']) \
    .mode("append") \
    .save()

job.commit()
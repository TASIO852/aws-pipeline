# --- 1. S3 Bucket (Data Lake) ---
resource "aws_s3_bucket" "datalake" {
  bucket = "${var.project_name}-datalake-${var.environment}"
  force_destroy = true # Permite destruir o bucket mesmo com arquivos (CUIDADO em prod)
}

resource "aws_s3_object" "glue_script" {
  bucket = aws_s3_bucket.datalake.id
  key    = "scripts/spark_etl.py"
  source = "../src/glue/spark_etl.py"
  etag   = filemd5("../src/glue/spark_etl.py")
}

# --- 2. Lambda (Ingestão Bronze) ---
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "../src/lambda/weather_ingestion.py"
  output_path = "lambda_function.zip"
}

resource "aws_lambda_function" "ingestion" {
  filename      = "lambda_function.zip"
  function_name = "${var.project_name}-ingest-bronze"
  role          = aws_iam_role.lambda_role.arn
  handler       = "weather_ingestion.lambda_handler"
  runtime       = "python3.9"
  timeout       = 60

  environment {
    variables = {
      BUCKET_NAME = aws_s3_bucket.datalake.id
      API_KEY     = var.openweather_api_key
    }
  }
}

# --- 3. Redshift Serverless (Gold) ---
# Nota: Redshift Serverless precisa de uma VPC configurada. 
# Para simplificar o teste, usaremos a default, mas em prod crie uma VPC.
resource "aws_redshiftserverless_namespace" "namespace" {
  namespace_name      = "${var.project_name}-namespace"
  admin_username      = var.db_user
  admin_user_password = var.db_password # Certifique-se que o nome da variável está correto aqui
  iam_roles           = [aws_iam_role.redshift_role.arn]
}

resource "aws_redshiftserverless_workgroup" "workgroup" {
  workgroup_name = "${var.project_name}-workgroup"
  namespace_name = aws_redshiftserverless_namespace.namespace.namespace_name
  base_capacity  = 8 # Mínimo para testes
  
  # Subnets e Security Groups devem ser configurados aqui para acesso via Glue
  # config_parameter { ... } 
}

# --- 4. AWS Glue Job (Silver & Gold) ---
resource "aws_glue_job" "etl" {
  name     = "${var.project_name}-etl-silver-gold"
  role_arn = aws_iam_role.glue_role.arn
  glue_version = "4.0"
  worker_type  = "G.1X"
  number_of_workers = 2

  command {
    script_location = "s3://${aws_s3_bucket.datalake.id}/scripts/spark_etl.py"
    python_version  = "3"
  }

  default_arguments = {
    "--BUCKET_NAME"        = aws_s3_bucket.datalake.id
    "--REDSHIFT_WORKGROUP" = aws_redshiftserverless_workgroup.workgroup.workgroup_name
    "--DB_USER"            = var.db_user
    "--DB_PASSWORD"        = var.db_password
    "--DB_NAME"            = "dev" # Database default do Redshift Serverless
    "--aws_region"          = "us-east-1"
  }
}

# --- 5. Step Functions (Orquestrador) ---
resource "aws_sfn_state_machine" "pipeline_orchestrator" {
  name     = "${var.project_name}-orchestrator"
  role_arn = aws_iam_role.step_functions_role.arn

  definition = <<EOF
{
  "Comment": "Orquestração do Pipeline de Dados Agrin",
  "StartAt": "IngestaoBronzeLambda",
  "States": {
    "IngestaoBronzeLambda": {
      "Type": "Task",
      "Resource": "${aws_lambda_function.ingestion.arn}",
      "Next": "TransformacaoGlue"
    },
    "TransformacaoGlue": {
      "Type": "Task",
      "Resource": "arn:aws:states:::glue:startJobRun.sync",
      "Parameters": {
        "JobName": "${aws_glue_job.etl.name}"
      },
      "End": true
    }
  }
}
EOF
}
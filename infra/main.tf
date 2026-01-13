# --- 1. S3 Bucket (Data Lake) ---
resource "aws_s3_bucket" "datalake" {
  bucket        = "${var.project_name}-datalake-${var.environment}"
  force_destroy = true 
}

# Upload do script Spark com detecção de alteração (etag)
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

# --- 3. Networking & Security (Redshift Access) ---
data "aws_vpc" "default" {
  default = true
}

# Busca todas as subnets da VPC padrão
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Security Group para abrir a porta do Redshift para o mundo (necessário para o Glue)
resource "aws_security_group" "redshift_sg" {
  name        = "${var.project_name}-redshift-sg"
  description = "Permite acesso ao Redshift vindo do Glue"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "Porta padrao Redshift"
    from_port   = 5439
    to_port     = 5439
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Permite que o Glue conecte via IP publico
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# --- 4. Redshift Serverless ---
resource "aws_redshiftserverless_namespace" "namespace" {
  namespace_name      = "${var.project_name}-namespace"
  admin_username      = var.db_user
  admin_user_password = var.db_password
  iam_roles           = [aws_iam_role.redshift_role.arn]
}

resource "aws_redshiftserverless_workgroup" "workgroup" {
  workgroup_name      = "${var.project_name}-workgroup"
  namespace_name      = aws_redshiftserverless_namespace.namespace.namespace_name
  base_capacity       = 8
  
  # Configuracoes cruciais para acesso externo
  publicly_accessible = true 
  security_group_ids  = [aws_security_group.redshift_sg.id]
  subnet_ids          = data.aws_subnets.default.ids
}

# --- 5. AWS Glue Job (ETL Silver & Gold) ---
resource "aws_glue_job" "etl" {
  name              = "${var.project_name}-etl-silver-gold"
  role_arn          = aws_iam_role.glue_role.arn
  glue_version      = "4.0"
  worker_type       = "G.1X"
  number_of_workers = 2

  command {
    script_location = "s3://${aws_s3_bucket.datalake.id}/scripts/spark_etl.py"
    python_version  = "3"
  }

  default_arguments = {
    "--BUCKET_NAME"         = aws_s3_bucket.datalake.id
    "--REDSHIFT_WORKGROUP"  = aws_redshiftserverless_workgroup.workgroup.workgroup_name
    "--DB_USER"             = var.db_user
    "--DB_PASSWORD"         = var.db_password
    "--DB_NAME"             = "dev"
    "--aws_region"          = "us-east-1"
    "--tempDir"             = "s3://${aws_s3_bucket.datalake.id}/temp/"
    "--extra-jars"          = "https://s3.amazonaws.com/redshift-downloads/drivers/jdbc/2.1.0.9/redshift-jdbc42-2.1.0.9.jar"
  }
}

# --- 6. Step Functions (Orquestrador) ---
resource "aws_sfn_state_machine" "pipeline_orchestrator" {
  name     = "${var.project_name}-orchestrator"
  role_arn = aws_iam_role.step_functions_role.arn

  definition = <<EOF
{
  "Comment": "Orquestracao do Pipeline de Dados Agrin",
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
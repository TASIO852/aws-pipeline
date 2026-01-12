variable "aws_region" { default = "us-east-1" }
variable "project_name" { default = "desafio-agrin" }
variable "environment" { default = "dev" }
variable "email_alerta" { description = "Seu email para o budget" }
variable "openweather_api_key" { description = "Sua chave da API OpenWeather" }
variable "db_user" { default = "admin" }
variable "db_password" { sensitive = true }
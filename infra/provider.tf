provider "aws" {
  region = var.aws_region
}

# Recurso de Orçamento (AWS Budgets)
resource "aws_budgets_budget" "custo_maximo" {
  name              = "budget-desafio-dados-15usd"
  budget_type       = "COST"
  limit_amount      = "15"
  limit_unit        = "USD"
  time_unit         = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.email_alerta]
  }
}
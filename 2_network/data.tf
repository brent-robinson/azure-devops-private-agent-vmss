# Client

data "azurerm_client_config" "current" {}

# Resource groups

data "azurerm_resource_group" "default" {
  name = "${var.project_code}-${var.environment_code}"
}

data "azuread_group" "administrators" {
  name = "${var.project_code}-${var.environment_code}-administrators"
}
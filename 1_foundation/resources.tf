locals {
  group_name           = "${var.project_code}-${var.environment_code}-administrators"
  application_name     = "${var.project_code}-${var.environment_code}"
  resource_group_name  = "${var.project_code}-${var.environment_code}"
  storage_account_name = "${var.project_code}${var.environment_code}${random_string.storage_account_suffix.result}"
}

################################################################################
# Group
################################################################################

resource "azuread_group" "administrators" {
  name = local.group_name

  depends_on = [
    azurerm_resource_group.default
  ]
}

resource "azuread_group_member" "administrators_service_principal" {
  group_object_id  = azuread_group.administrators.id
  member_object_id = azuread_service_principal.default.object_id
}

################################################################################
# Service Principal
################################################################################

resource "azuread_application" "default" {
  name = local.application_name

  depends_on = [
    azurerm_resource_group.default
  ]
}

resource "azuread_service_principal" "default" {
  application_id = azuread_application.default.application_id
}

resource "azuread_service_principal_password" "default" {
  service_principal_id = azuread_service_principal.default.id
  value                = random_password.default.result
  end_date_relative    = "87600h" # 10 years
}

resource "random_password" "default" {
  length      = 80
  min_upper   = 1
  min_lower   = 1
  min_numeric = 1
  min_special = 1
}

################################################################################
# Resource Group
################################################################################

resource "azurerm_resource_group" "default" {
  name     = local.resource_group_name
  location = var.location
}

resource "azurerm_role_assignment" "default" {
  scope                = azurerm_resource_group.default.id
  role_definition_name = "Owner"
  principal_id         = azuread_group.administrators.id
}

################################################################################
# Storage
################################################################################

resource "azurerm_storage_account" "default" {
  name                      = local.storage_account_name
  resource_group_name       = azurerm_resource_group.default.name
  location                  = azurerm_resource_group.default.location
  account_kind              = "StorageV2"
  account_tier              = "Standard"
  account_replication_type  = "GRS"
  enable_https_traffic_only = true

  tags = {
    app = var.project_code
    env = var.environment_code
  }
}

resource "azurerm_storage_container" "terraform" {
  name                  = "terraform"
  storage_account_name  = azurerm_storage_account.default.name
  container_access_type = "private"
}

resource "random_string" "storage_account_suffix" {
  length  = 8
  special = false
  upper   = false
  lower   = false
}

locals {
  virtual_network_name   = "${var.project_code}-${var.environment_code}"
  agents_subnet_nsg_name = "${var.project_code}-${var.environment_code}-agents"
  public_ip_name         = "${var.project_code}-${var.environment_code}-agents"
  load_balancer_name     = "${var.project_code}-${var.environment_code}-agents"
  managed_identity_name  = "${var.project_code}-${var.environment_code}-agents"
  key_vault_name         = "${var.project_code}-${var.environment_code}-agents-${random_string.key_vault_suffix.result}"
}

################################################################################
# Virtual Network
################################################################################

# Network
# -------

resource "azurerm_virtual_network" "default" {
  name                = local.virtual_network_name
  resource_group_name = data.azurerm_resource_group.default.name
  location            = data.azurerm_resource_group.default.location

  address_space = [var.network_cidr]

  tags = {
    app = var.project_code
    env = var.environment_code
  }
}

# Subnet
# ------

resource "azurerm_subnet" "agents" {
  name                 = "agents"
  resource_group_name  = data.azurerm_resource_group.default.name
  virtual_network_name = azurerm_virtual_network.default.name

  address_prefix            = var.agents_subnet_cidr
  network_security_group_id = azurerm_network_security_group.agents.id

  /*service_endpoints = [
    "Microsoft.AzureActiveDirectory",
    "Microsoft.KeyVault",
    "Microsoft.Sql",
    "Microsoft.Storage",
  ]*/
}

# Network Security Group
# ----------------------

resource "azurerm_network_security_group" "agents" {
  name                = local.agents_subnet_nsg_name
  resource_group_name = data.azurerm_resource_group.default.name
  location            = data.azurerm_resource_group.default.location

  tags = {
    app = var.project_code
    env = var.environment_code
  }
}

resource "azurerm_subnet_network_security_group_association" "agents" {
  subnet_id                 = azurerm_subnet.agents.id
  network_security_group_id = azurerm_network_security_group.agents.id
}

################################################################################
# Public IP
################################################################################

resource "azurerm_public_ip" "default" {
  name                = local.public_ip_name
  resource_group_name = data.azurerm_resource_group.default.name
  location            = data.azurerm_resource_group.default.location

  sku               = "Standard"
  allocation_method = "Static"

  tags = {
    app = var.project_code
    env = var.environment_code
  }
}

################################################################################
# Load Balancer
################################################################################

resource "azurerm_lb" "default" {
  name                = local.load_balancer_name
  resource_group_name = data.azurerm_resource_group.default.name
  location            = data.azurerm_resource_group.default.location

  sku = "Standard"

  frontend_ip_configuration {
    name                 = "public"
    public_ip_address_id = azurerm_public_ip.default.id
  }

  tags = {
    app = var.project_code
    env = var.environment_code
  }
}

################################################################################
# Managed Identity
################################################################################

resource "azurerm_user_assigned_identity" "default" {
  name                = local.managed_identity_name
  resource_group_name = data.azurerm_resource_group.default.name
  location            = data.azurerm_resource_group.default.location

  tags = {
    app = var.project_code
    env = var.environment_code
  }
}

################################################################################
# Key Vault
################################################################################

resource "azurerm_key_vault" "default" {
  name                = local.key_vault_name
  resource_group_name = data.azurerm_resource_group.default.name
  location            = data.azurerm_resource_group.default.location

  tenant_id = data.azurerm_client_config.current.tenant_id
  sku_name  = "standard"

  tags = {
    app = var.project_code
    env = var.environment_code
  }
}

resource "azurerm_key_vault_access_policy" "default" {
  key_vault_id       = azurerm_key_vault.default.id
  tenant_id          = data.azurerm_client_config.current.tenant_id
  object_id          = azurerm_user_assigned_identity.default.principal_id
  secret_permissions = ["get"]
}

resource "azurerm_key_vault_access_policy" "administrators" {
  key_vault_id       = azurerm_key_vault.default.id
  tenant_id          = data.azurerm_client_config.current.tenant_id
  object_id          = data.azuread_group.administrators.id
  secret_permissions = ["list", "get", "set"]
}

resource "azurerm_role_assignment" "default" {
  scope                = azurerm_key_vault.default.id
  role_definition_name = "Reader"
  principal_id         = azurerm_user_assigned_identity.default.principal_id
}

resource "random_string" "key_vault_suffix" {
  length  = 8
  special = false
  upper   = false
  lower   = false
}

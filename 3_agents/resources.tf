locals {
  load_balancer_address_pool_name          = "${var.project_code}-${var.environment_code}-agents"
  virtual_machine_scale_set_name           = "${var.project_code}-${var.environment_code}-agents"
  virtual_machine_scale_set_prefix         = "${var.project_code}${var.environment_code}"
  virtual_machine_scale_set_admin_username = "${var.project_code}${var.environment_code}"
  storage_account_name                     = "${var.project_code}${var.environment_code}agents${random_string.storage_account_suffix.result}"
}

################################################################################
# Virtual Machine Scale Set
################################################################################

resource "azurerm_virtual_machine_scale_set" "default" {
  name                = local.virtual_machine_scale_set_name
  resource_group_name = data.azurerm_resource_group.default.name
  location            = data.azurerm_resource_group.default.location

  upgrade_policy_mode = "Manual"

  sku {
    name     = var.vmss_sku_name
    tier     = var.vmss_sku_tier
    capacity = 0
  }

  storage_profile_image_reference {
    publisher = var.vmss_image_publisher
    offer     = var.vmss_image_offer
    sku       = var.vmss_image_sku
    version   = var.vmss_image_version
  }

  storage_profile_os_disk {
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }

  os_profile {
    computer_name_prefix = local.virtual_machine_scale_set_prefix
    admin_username       = local.virtual_machine_scale_set_admin_username
    admin_password       = random_password.vmss_admin_password.result
  }

  os_profile_windows_config {
    provision_vm_agent        = true
    enable_automatic_upgrades = true
  }

  network_profile {
    name    = "default"
    primary = true

    ip_configuration {
      name                                   = "default"
      primary                                = true
      subnet_id                              = data.azurerm_subnet.default.id
      load_balancer_backend_address_pool_ids = [azurerm_lb_backend_address_pool.default.id]
      load_balancer_inbound_nat_rules_ids    = [azurerm_lb_nat_pool.rdp.id]
    }
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [data.azurerm_user_assigned_identity.default.id]
  }

  boot_diagnostics {
    enabled     = true
    storage_uri = azurerm_storage_account.default.primary_blob_endpoint
  }

  extension {
    name                       = "HealthExtension"
    publisher                  = "Microsoft.ManagedServices"
    type                       = "ApplicationHealthWindows"
    type_handler_version       = "1.0"
    auto_upgrade_minor_version = true
    settings                   = <<SETTINGS
    {
        "protocol" : "tcp",
        "port" : "3389"
    }
SETTINGS
  }

  extension {
    name                       = "AzureDevOpsAgent"
    publisher                  = "Microsoft.Compute"
    type                       = "CustomScriptExtension"
    type_handler_version       = "1.9"
    auto_upgrade_minor_version = true
    settings                   = <<SETTINGS
    {
        "fileUris" : [
          "${azurerm_storage_blob.default.url}"
        ],
        "timestamp" : 10
    }
SETTINGS
    protected_settings         = <<PROTECTEDSETTINGS
    {
        "commandToExecute" : "powershell -ExecutionPolicy Unrestricted -File Configure-Agent.ps1 -Pool \"${var.azdo_pool_name}\"",
        "storageAccountName" : "${azurerm_storage_account.default.name}",
        "storageAccountKey" : "${azurerm_storage_account.default.primary_access_key}"
    }
PROTECTEDSETTINGS
  }

  tags = {
    app = var.project_code
    env = var.environment_code
  }

  lifecycle {
    ignore_changes = [
      sku[0].capacity
    ]
  }
}

resource "azurerm_lb_backend_address_pool" "default" {
  name                = local.load_balancer_address_pool_name
  resource_group_name = data.azurerm_resource_group.default.name
  loadbalancer_id     = data.azurerm_lb.default.id
}

resource "azurerm_lb_nat_pool" "rdp" {
  name                = "rdp"
  resource_group_name = data.azurerm_resource_group.default.name
  loadbalancer_id     = data.azurerm_lb.default.id

  protocol                       = "Tcp"
  frontend_port_start            = 50000
  frontend_port_end              = 50099
  backend_port                   = 3389
  frontend_ip_configuration_name = "public"
}

resource "azurerm_lb_probe" "rdp" {
  name                = "rdp"
  resource_group_name = data.azurerm_resource_group.default.name
  loadbalancer_id     = data.azurerm_lb.default.id

  protocol = "Tcp"
  port     = 3389
}

resource "azurerm_lb_rule" "default" {
  name                = "ephemeral"
  resource_group_name = data.azurerm_resource_group.default.name
  loadbalancer_id     = data.azurerm_lb.default.id

  protocol                       = "Tcp"
  frontend_port                  = 65000
  backend_port                   = 65000
  frontend_ip_configuration_name = "public"
  backend_address_pool_id        = azurerm_lb_backend_address_pool.default.id
  probe_id                       = azurerm_lb_probe.rdp.id
}

resource "random_password" "vmss_admin_password" {
  length = 16
}

################################################################################
# Storage Account
################################################################################

resource "azurerm_storage_account" "default" {
  name                = local.storage_account_name
  resource_group_name = data.azurerm_resource_group.default.name
  location            = data.azurerm_resource_group.default.location

  account_kind              = "StorageV2"
  account_tier              = "Standard"
  account_replication_type  = "LRS"
  enable_https_traffic_only = true

  tags = {
    app = var.project_code
    env = var.environment_code
  }
}

resource "azurerm_storage_container" "scripts" {
  name                  = "scripts"
  storage_account_name  = azurerm_storage_account.default.name
  container_access_type = "private"
}

resource "azurerm_storage_blob" "default" {
  name                   = "Configure-Agent.ps1"
  resource_group_name    = data.azurerm_resource_group.default.name
  storage_account_name   = azurerm_storage_account.default.name
  storage_container_name = azurerm_storage_container.scripts.name
  type                   = "block"
  source                 = "${path.module}/Configure-Agent.ps1"
}

resource "random_string" "storage_account_suffix" {
  length  = 8
  special = false
  upper   = false
  lower   = false
}

output "public_ip_address" {
  value = azurerm_public_ip.default.ip_address
}

output "key_vault_name" {
  value = azurerm_key_vault.default.name
}

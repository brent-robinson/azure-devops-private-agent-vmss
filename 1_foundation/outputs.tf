output "storage_account_name" {
  value = azurerm_storage_account.default.name
}

output "storage_access_key" {
  value = azurerm_storage_account.default.primary_access_key
}

output "service_principal_client_id" {
  value = azuread_service_principal.default.application_id
}

output "service_principal_client_secret" {
  value = random_password.default.result
}

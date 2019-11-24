output "vmss_username" {
  value = local.virtual_machine_scale_set_admin_username
}

output "vmss_password" {
  value = random_password.vmss_admin_password.result
}


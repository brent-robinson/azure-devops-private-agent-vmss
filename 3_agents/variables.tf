variable "project_code" {
  default = "azdo"
}

variable "environment_code" {
  default = "dev"
}

variable "vmss_sku_name" {
  default = "Standard_B2s"
}

variable "vmss_sku_tier" {
  default = "Standard"
}

variable "vmss_image_publisher" {
  default = "MicrosoftWindowsServer"
}

variable "vmss_image_offer" {
  default = "WindowsServer"
}

variable "vmss_image_sku" {
  default = "2019-Datacenter"
}

variable "vmss_image_version" {
  default = "latest"
}

variable "azdo_pool_name" {
  default = "Private"
}

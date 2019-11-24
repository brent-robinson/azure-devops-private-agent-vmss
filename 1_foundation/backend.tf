terraform {
  backend "azurerm" {
    container_name = "terraform"
    key            = "1_foundation.tfstate"
  }
}

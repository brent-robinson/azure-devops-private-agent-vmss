terraform {
  backend "azurerm" {
    container_name = "terraform"
    key            = "2_network.tfstate"
  }
}

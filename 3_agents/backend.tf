terraform {
  backend "azurerm" {
    container_name = "terraform"
    key            = "3_agents.tfstate"
  }
}

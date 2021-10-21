terraform {
  backend "azurerm" {
    workspaces {
      prefix = "aws-agent-"
    }
  }
}

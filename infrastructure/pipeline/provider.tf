terraform {
  required_providers {
    azuredevops = {
      source  = "microsoft/azuredevops"
      version = ">=0.1.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=2.46.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "3.0.0"
    }
  }
}

provider "aws" {
  region = "eu-west-2"
}

provider "azurerm" {
  features {}
}

provider "tls" {}

# Pool creation

resource "azuredevops_agent_pool" "pool" {
  name           = var.azdevops_agent_pool_name
  auto_provision = false
}

data "azuredevops_project" "project" {
  name = var.azdevops_existing_project_name
}

resource "azuredevops_agent_queue" "pool_project_queue" {
  project_id    = data.azuredevops_project.project.id
  agent_pool_id = azuredevops_agent_pool.pool.id
}

# PAT rotation

resource "time_rotating" "pat_time" {
  rotation_months = 11
}

resource "random_pet" "pat_encoding" {
  keepers = {
    time = time_rotating.pat_time.rotation_rfc3339
  }
}

locals {
  pat_token_body = jsonencode({
    displayName = "agent-token-${azuredevops_agent_pool.pool.name}-${random_pet.pat_encoding.id}"
    scope       = "vso.agentpools_manage"
    validTo     = time_rotating.pat_time.rotation_rfc3339
    allOrgs     = false
  })
  azdevops_resource_id = "499b84ac-1321-427f-aa17-267ca6975798"
}

locals {
  pat_mapped_response  = jsondecode(module.create_pat_token.stdout)
  pat_authorization_id = local.pat_mapped_response.patToken.authorizationId
  pat_token            = local.pat_mapped_response.patToken.token
}

module "create_pat_token" {
  source = "matti/resource/shell"

  command = <<-EOT
    az rest \
    --method post \
    --url "https://vssps.dev.azure.com/${var.azdevops_organisation_name}/_apis/tokens/pats?api-version=6.1-preview.1" \
    --headers "Content-Type=application/json" \
    --resource "${local.azdevops_resource_id}" \
    --body '${local.pat_token_body}'
  EOT

  sensitive_outputs = true
}

locals {
  aws_common_tags = {
    agent_type = "ado"
    agent_pool = var.azdevops_agent_pool_name
  }
}

resource "aws_vpc" "main" {
  cidr_block       = "10.0.0.0/16"
  instance_tenancy = "default"

  tags = local.aws_common_tags
}

resource "aws_resourcegroups_group" "rg" {
  name = "rg-${var.azdevops_agent_pool_name}"
  tags = local.aws_common_tags
  resource_query {
    query = <<JSON
{
  "ResourceTypeFilters": ["AWS::AllSupported"],
  "TagFilters": [
    {
      "Key": "agent_pool",
      "Values": ["${var.azdevops_agent_pool_name}"]
    }
  ]
}
JSON
  }
}

resource "aws_subnet" "main" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.1.0/24"
  tags = local.aws_common_tags
}

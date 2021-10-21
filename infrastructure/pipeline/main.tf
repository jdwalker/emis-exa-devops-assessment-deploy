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

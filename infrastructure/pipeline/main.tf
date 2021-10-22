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
  pat_mapped_response  = jsondecode(module.create_pat_token.stdout)
  pat_authorization_id = local.pat_mapped_response.patToken.authorizationId
  pat_token            = local.pat_mapped_response.patToken.token
}

# AWS

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

resource "aws_eip" "internet" {
  vpc = true
}


resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
  tags   = local.aws_common_tags
}


# Networking part taken from https://medium.com/appgambit/terraform-aws-vpc-with-private-public-subnets-with-nat-4094ad2ab331

/* Public subnet */
resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.3.0/24"
  map_public_ip_on_launch = true
  tags = merge(local.aws_common_tags, {
    Name = "public-subnet"
  })
}


resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.internet.id
  subnet_id     = aws_subnet.public_subnet.id

  tags = merge(local.aws_common_tags, {
    Name = "Gateway NAT"
  })

  depends_on = [aws_internet_gateway.gw]
}

/* Private subnet */
resource "aws_subnet" "private_subnet" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  map_public_ip_on_launch = false
  tags = merge(local.aws_common_tags, {
    Name = "public-subnet"
  })
}
/* Routing table for private subnet */
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  tags = merge(local.aws_common_tags, {
    Name = "private-route-table"
  })
}
/* Routing table for public subnet */
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  tags = merge(local.aws_common_tags, {
    Name = "public-route-table"
  })
}

resource "aws_route" "public_internet_gateway" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.gw.id
}

resource "aws_route" "private_nat_gateway" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat.id
}

/* Route table associations */
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private_subnet.id
  route_table_id = aws_route_table.private.id
}

resource "aws_resourcegroups_group" "rg" {
  name = "rg-${var.azdevops_agent_pool_name}"
  tags = local.aws_common_tags
  resource_query {
    query = jsonencode(
      {
        "ResourceTypeFilters" : ["AWS::AllSupported"]
        TagFilters = [
          {
            Key    = "agent_pool"
            Values = ["${var.azdevops_agent_pool_name}"]
          }
        ]
    })
  }
}

# Generate private key for key pair
resource "tls_private_key" "ssh" {
  algorithm = "RSA"
  rsa_bits  = "4096"
}

resource "local_file" "private_key" {
  content         = tls_private_key.ssh.private_key_pem
  filename        = "aws-agent-private-key-${var.azdevops_agent_pool_name}.pem"
  file_permission = "0600"
}

resource "aws_key_pair" "deployer" {
  public_key = chomp(tls_private_key.ssh.public_key_openssh)
  tags       = local.aws_common_tags
}

resource "aws_iam_role" "agent" {
  managed_policy_arns = ["arn:aws:iam::aws:policy/PowerUserAccess"]
  tags                = local.aws_common_tags
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_instance_profile" "profile" {
  role = aws_iam_role.agent.name
  tags = local.aws_common_tags
}

# Forked from https://github.com/sderen/terraform-azure-devops-self-hosted-agent-on-aws
module "selfhostedagent" {
  source            = "github.com/jdwalker/terraform-azure-devops-self-hosted-agent-on-aws"
  vpc_id            = aws_vpc.main.id
  subnet_ids        = [aws_subnet.public_subnet.id]
  azuredevops_url   = "https://dev.azure.com/${var.azdevops_organisation_name}"
  azuredevops_token = local.pat_token
  azuredevops_pool  = var.azdevops_agent_pool_name
  key_name          = aws_key_pair.deployer.key_name
  instance_type     = "t3a.small"
  asg_max_size      = 1
  asg_min_size      = 1
  asg_desired_size  = 1
  tags              = local.aws_common_tags
  ami_id            = "ami-0194c3e07668a7e36"
  depends_on = [
    aws_route.private_nat_gateway
  ]
  iam_instance_profile_arn = aws_iam_instance_profile.profile.arn
  environment_variables = {
    #   TF_CLI_ARGS_init = "--backend-config=\"bucket=${var.tf_store_name}\" --backend-config=\"key=tfstore}\" \""
    AWS_REGION = "eu-west-2"
  }
}

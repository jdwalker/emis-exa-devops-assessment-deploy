# exa-devops-assignment-deploy
Deployment of exa devops assignment

This is a setup of a deployment of the following pieces to create a connection for CI/CD between a AzureDevops and an AWS account:

- An AWS VPC
- An AWS EC2 build agent, with ado and docker
- An AWS IAM role for that build agent
- A parameter store with credentials for the agent from ado
- An S3 bucket for terraform state

We need the following preexisting resources (this can be set up by terraform, but this keeps it simple):

- An Azure Active Directory
- An Azure Devops Organisation and Project
- An Azure Devops Admin CI user credentialsv with AD access
- A secure Azure blob for the terraform backend
- An AWS account for our deployment environment

# Setup

- Copy the local.env file to .env
 - Fill in the .env details - this can be account level and not per user so the CI user doesn't need direct access to the backend subscription
  - Copy the security/security.env file to security/.env
 - Fill in the .env details - this can be account level and not per user so the CI user doesn't need direct access to the backend subscription

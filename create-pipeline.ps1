#!/usr/bin/env pwsh

$ErrorActionPreference = "Stop"

function RunAndHaltOnFailure() {
    $command,$commandArgs = $args
    $result = & $command $commandArgs
    if($LASTEXITCODE -ne 0) {  throw "Command '$command $commandArgs' failed!"}
    return $result
}

$currentDirectory = Get-Location
trap { Set-Location $currentDirectory }
$ScriptDir = Split-Path $script:MyInvocation.MyCommand.Path
$RepoDir = Join-Path $ScriptDir "."
Push-Location $RepoDir
Set-PsEnv

Push-Location ./infrastructure/pipeline

if($env:AZURE_CLI_SKIP_FORCE_LOGIN -ne "true") {

Write-Host "Login to team CI User, press any key to continue"
$null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown');
$tempDir = RunAndHaltOnFailure mktemp -d
Write-Host "Storing temp azure config in '$tempDir'"

$env:AZURE_CONFIG_DIR=$tempDir
RunAndHaltOnFailure az login --allow-no-subscriptions --tenant $env:ARM_TENANT_ID
}

Write-Host "Retrieving Azure Devops Token"

# Generate temporary access_token for azure devops
# Partially from https://gist.github.com/dylanberry/7c7c4e8746270fcee207981e5b0d9b10#file-azuredevops-get-pat-az-cli-ps1
$azureDevopsResourceId = "499b84ac-1321-427f-aa17-267ca6975798"
$token = RunAndHaltOnFailure az account get-access-token --resource $azureDevopsResourceId --tenant $env:ARM_TENANT_ID
$token = ConvertFrom-Json ($token -join "")
$env:AZDO_PERSONAL_ACCESS_TOKEN = $token.accessToken
$env:AZDO_ORG_SERVICE_URL = "https://dev.azure.com/$env:TF_VAR_azdevops_organisation_name" 

Write-Host "Initialising"

RunAndHaltOnFailure terraform init `
    -backend-config="storage_account_name=$env:AZURE_BACKEND_STORAGE_ACCOUNT_NAME" `
    -backend-config="container_name=$env:AZURE_BACKEND_CONTAINER_NAME" `
    -backend-config="key=$env:AZURE_BACKEND_KEY" `
    -reconfigure `
    -input=false

$tempPath = RunAndHaltOnFailure mktemp

Write-Host "Planning..."

RunAndHaltOnFailure terraform plan -out $tempPath

Write-Host "Applying"

RunAndHaltOnFailure terraform apply $tempPath

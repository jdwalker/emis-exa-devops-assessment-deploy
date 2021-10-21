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

Write-Host "Login to team CI User"
$tempDir = RunAndHaltOnFailure mktemp -d
$env:AZURE_CONFIG_DIR=$tempDir
RunAndHaltOnFailure az login --allow-no-subscriptions

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

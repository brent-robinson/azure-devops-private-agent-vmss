param (
    $Pool,
    $InstallDirectory = "D:\azdo"
)

$ErrorActionPreference = "Stop"

# Start transcription
Start-Transcript -Path (Join-Path -Path $env:TEMP -ChildPath "configure-agent.log") -Append

# Get an access token to query Azure Resource Manager
Write-Output "Acquiring access token"
$armTokenResponse = Invoke-WebRequest -Uri 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https%3A%2F%2Fmanagement.azure.com%2F' -Headers @{Metadata = "true" } -UseBasicParsing | Select-Object -ExpandProperty Content | ConvertFrom-Json
$armToken = $armTokenResponse.access_token

# Get the subscription id
Write-Output "Finding subscription id"
$subscriptionsResponse = Invoke-WebRequest -Uri "https://management.azure.com/subscriptions?api-version=2019-06-01" -ContentType "application/json" -Headers @{ Authorization = "Bearer $armToken" } -UseBasicParsing | Select-Object -ExpandProperty Content | ConvertFrom-Json
$subscriptionId = $subscriptionsResponse.value[0].subscriptionId

# Find all key vaults in the subscription (should be only 1 visible)
Write-Output "Finding key vaults"
$keyVaultsResponse = Invoke-WebRequest -Uri "https://management.azure.com/subscriptions/$subscriptionId/resources?$filter=resourceType eq 'Microsoft.KeyVault/vaults'&api-version=2019-08-01" -ContentType "application/json" -Headers @{ Authorization = "Bearer $armToken" } -UseBasicParsing | Select-Object -ExpandProperty Content | ConvertFrom-Json
$keyVaultName = $keyVaultsResponse.value[0].name

# Get an access token to query the key vault
Write-Output "Acquiring key vault access token"
$keyVaultTokenResponse = Invoke-WebRequest -Uri 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https%3A%2F%2Fvault.azure.net' -Headers @{Metadata = "true" } -UseBasicParsing | Select-Object -ExpandProperty Content | ConvertFrom-Json
$keyVaultToken = $keyVaultTokenResponse.access_token

# Get the Azure DevOps URL from the key vault secret
Write-Output "Finding key vault secrets"
$secretResponse = Invoke-WebRequest -Uri "https://$keyVaultName.vault.azure.net/secrets/AzureDevOps--Url/?api-version=7.0" -ContentType "application/json" -Headers @{ Authorization = "Bearer $keyVaultToken" } -UseBasicParsing | Select-Object -ExpandProperty Content | ConvertFrom-Json
$url = $secretResponse.value
$secretResponse = Invoke-WebRequest -Uri "https://$keyVaultName.vault.azure.net/secrets/AzureDevOps--Pat/?api-version=7.0" -ContentType "application/json" -Headers @{ Authorization = "Bearer $keyVaultToken" } -UseBasicParsing | Select-Object -ExpandProperty Content | ConvertFrom-Json
$pat = $secretResponse.value
$secretResponse = Invoke-WebRequest -Uri "https://$keyVaultName.vault.azure.net/secrets/AzureDevOps--InstallPackage--WinX64/?api-version=7.0" -ContentType "application/json" -Headers @{ Authorization = "Bearer $keyVaultToken" } -UseBasicParsing | Select-Object -ExpandProperty Content | ConvertFrom-Json
$installPackage = $secretResponse.value
Write-Output "Url = $url"
Write-Output "Install Package = $installPackage"

# Download the agent package
Write-Output "Downloading agent"
$packageFile = Join-Path -Path $env:TEMP -ChildPath "agent.zip"
Invoke-WebRequest -UseBasicParsing -Uri $installPackage -OutFile $packageFile

# Ensure the work directory is empty
Write-Output "Creating directory"
if (Test-Path -Path $InstallDirectory) {
    Remove-Item -Path $InstallDirectory -Recurse | Out-Null
}

# Expand the agent to the work directory
Write-Output "Extracting agent"
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::ExtractToDirectory($packageFile, $InstallDirectory)

# Configure the agent
Write-Output "Configuring agent"
Set-Location $InstallDirectory
.\config.cmd --unattended --url $url --auth pat --token $pat --pool $Pool --replace --runAsService

# Stop transcription
Write-Output "Done"
Stop-Transcript

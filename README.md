# Introduction

This repository contains Terraform templates used to build private agents for Azure DevOps. The agents will be part of a Virtual Machine Scale Set, and configured with a script extension to automatically configure and register with Azure DevOps as instances start. A load balancer is used to ensure all the instances use the same outbound IP address. This solution can be extended to configure VNet peering and Service Endpoints to meet the specific requirements of an environment.

# Getting Started

## Prerequisites

You will need the following software on your machine. All the tools are cross-platform.

* PowerShell Core 6+
* Azure CLI
* Terraform 0.12

With slight tweaks to some commands, you can use your preferred terminal instead of PowerShell.

You will also need an Azure tenant with:

* A subscription you can create resources and assign permissions (`Owner` role).
* Azure Active Directory permission to create a Service Principal, Application, and Group.

## Provision an agent pool

These instructions will create a new private agent set in Azure. A storage account will be created and configured as a remote backend for the Terraform state.

### Foundation

The `foundation` Terraform configuration creates an Azure storage account and configures it as the Terraform backend. The Terraform state is then migrated to the storage account. The Terraform configuration will also create resources that require privileges on the Azure subscription and Azure Active Directory (AAD), such as a resource group, service principal, and an AAD group. Any user with access to the created AAD group will be able to complete the remaining steps of these instructions after the foundation is created. Users can be added manually or defined in the foundation Terraform configuration.

1. Login to Azure and select a subscription.

```powershell
az login --tenant "<your tenant id>"
az account set --subscription "<your subscription name>"
```

2. Move to the `1_foundation` directory.

```powershell
Set-Location -Path ./1_foundation
```

3. Disable the backend.

```powershell
Move-Item -Path ./backend.tf -Destination ./backend.tf.disabled
```

4. Initialise and apply the Terraform configuration.

```powershell
terraform init
terraform apply
```

5. Retrieve the configuration of the Azure storage account to use as a backend.

```powershell
$stateStorageAccountName = terraform output storage_account_name
$stateStorageAccessKey = terraform output storage_access_key
```

6. Enable the backend.

```powershell
Move-Item -Path .\backend.tf.disabled -Destination .\backend.tf
```

7. Move the Terraform state file to the remote backend.

```powershell
terraform init -force-copy `
-backend-config="storage_account_name=$stateStorageAccountName" `
-backend-config="access_key=$stateStorageAccessKey"
```

8. Remove the local backups of the Terraform state files.

```powershell
Remove-Item "terraform.tfstate" -ErrorAction SilentlyContinue
Remove-Item "terraform.tfstate.backup" -ErrorAction SilentlyContinue
```

### Shared Components

The `network` Terraform configuration will create the network resources required for the agents, including the virtual network, subnet, public IP, and load balancer. A managed identity and key vault will also be created to be used by the agents to retrieve sensitive configuration information. The configuration is used to set up the agent virtual machine when it starts.

1. Move to the `2_network` directory.

```powershell
Set-Location -Path ../2_network
```

2. Initialise Terraform with the remote backend.

```powershell
terraform init -backend-config="storage_account_name=$stateStorageAccountName" -backend-config="access_key=$stateStorageAccessKey"
```

3. Apply the Terraform configuration.

```
terraform apply
```

### Azure DevOps Configuration

The creation of the agents will require configuration to download the Azure DevOps agent software and configure it to connect to your Azure DevOps instance.

1. From Azure DevOps, generate a Personal Acess Token (PAT). This option is in your user settings. You should only grant the minimal scope required. You can use any name and expiry, though a longer expiry is recommended. Record the generated PAT - you'll need it later.

* **Name:** Azure DevOps Pipeline Agent Registration
* **Expiry:** 1 year
* **Scopes:** `Read & Manage` agent pools (you need to select "Show all scopes" to see this option)

2. Create an agent pool in Azure DevOps. You can also reuse an existing agent pool. You can find this in the "Agent Pools" section of both "Organisation Settings" and "Project Settings". Record the agent pool name - you'll need it later.

3. Find the path to the latest installation package for the Azure DevOps agent software. Open the agent pool and select the `New Agent` button. Select `Windows` at the top then `X64` on the left. Copy the agent package location using the button under `Download the agent`. Record the URL - you'll need it later.

4. Add to yourself as a member of the "administrators" group created by the Terraform configuration. By default, it's named `azdo-dev-administrators`.

5. Locate the Azure Key Vault created in the previous Terraform configuration. Create the below secrets. If you receive a message indicating you don't have permission, ensure you're added to the group in the previous step, sign out the Azure Portal, and sign back in.

| Key                                 | Value                                                                                                              |
| ----------------------------------- | ------------------------------------------------------------------------------------------------------------------ |
| AzureDevOps--Url                    | *The URL of your Azure DevOps instance, e.g. `https://dev.azure.com/myazdo` or `https://myazdo.visualstudio.com`.* |
| AzureDevOps--Pat                    | *The PAT token generated in the first step.*                                                                       |
| AzureDevOps--InstallPackage--WinX64 | *The path to the latest agent installation package.*                                                               |

### Agents

The `agents` Terraform configuration will create the virtual machine scale set that hosts the agents. The instances of the scale set will be added to a new backend pool on the load balancer to share the same public IP address. A storage account is created to store the script used to configure the virtual machines when they start.

1. Move to the `3_agents` directory.

```powershell
Set-Location -Path ../3_agents
```

2. Initialise Terraform with the remote backend.

```powershell
terraform init -backend-config="storage_account_name=$stateStorageAccountName" -backend-config="access_key=$stateStorageAccessKey"
```

3. Update your pool name in the `variables.tf` file or pass it into the next step as a variable parameter. The variable is named `azdo_pool_name`. You may want to review other default variables which define the virtual machine SKU and image.

3. Apply the Terraform configuration.

```
terraform apply
```

### Launching the agents

By default, this configuration won't provision any agent instances automatically. When the Terraform configuration is applied, locate the Virtual Machine Scale Set in the Azure Portal. On the "Scaling" blade, you can increase the number of instances. You can monitor the creation of these instances from the "Instances" blade. If you have changing workload requirements, you can configure autoscaling based on the time of day.

When instances are provisioning, you may see that an additional instance. This "overprovisioning" is standard for virtual machine scale sets. You can turn it off; however, the additional instance is not charged. Whichever instance successfully starts first is kept.

# Operations

## Continue and re-run the Terraform configuration

To continue in a new PowerShell session after creating the foundation, you'll need to manually set the `$stateStorageAccountName` and `$stateStorageAccessKey` variables. You can retrieve these from the created storage account in the Azure portal.

You may need to initialise each Terraform configuration by running the `init` command and passing in the backend configuration.

```powershell
terraform init -backend-config="storage_account_name=$stateStorageAccountName" -backend-config="access_key=$stateStorageAccessKey"
```

You can then run Terraform commands as usual.

## Destroy an agent pool

To tear down the pool created, you'll need to delete the Azure resources, remove the created pool from Azure DevOps, and delete your PAT.

1. Login to Azure and select a subscription.

```powershell
az login --tenant "<your tenant id>"
az account set --subscription "<your subscription name>"
```

2. Ensure the `$stateStorageAccountName` and `$stateStorageAccessKey` variables are set in your session (see above section).

3. Destroy the agent configuration.

```powershell
Set-Location -Path ./3_agents
terraform init -backend-config="storage_account_name=$stateStorageAccountName" -backend-config="access_key=$stateStorageAccessKey"
terraform destroy
```

4. Destroy the network configuration.

```powershell
Set-Location -Path ../2_network
terraform init -backend-config="storage_account_name=$stateStorageAccountName" -backend-config="access_key=$stateStorageAccessKey"
terraform destroy
```

5. Destroy the foundation configuration. We'll first move the Terraform state back to local to avoid an error as we're deleting the remote backend in this step.

```powershell
Set-Location -Path ../1_foundation
Move-Item -Path .\backend.tf -Destination .\backend.tf.disabled
terraform init -force-copy
terraform destroy

Remove-Item "terraform.tfstate" -ErrorAction SilentlyContinue
Remove-Item "terraform.tfstate.backup" -ErrorAction SilentlyContinue
Move-Item -Path .\backend.tf.disabled -Destination .\backend.tf
```

## Debug an instance

You can use Remote Desktop Protocol (RDP) or the Serial Console to investigate any issues.

Noteworthy files to check when instance provisioning fails are:

* C:\WindowsAzure\Logs\Plugins\Microsoft.Compute.CustomScriptExtension\1.10.3\CustomScriptHandler.log
* c:\Windows\Temp\configure-agent.log

### Serial console:

1. In the Azure Portal, navigate to the Virtual Machine Scale Set.

2. Open the "Instances" blade.

3. Select the instance you want to connect to.

4. Open the "Serial console" blade.

5. Enter `cmd` when the prompt loads.

6. Enter `ch -si 1` then press enter when the prompt loads.

7. Enter the credentials of the virtual machine (output from the Terraform `agent` configuration). Leave the domain field blank.

You'll then enter a command prompt session within the virtual machine. You can navigate around the machine and view log files.

### RDP

1. Add a rule to the Network Security Group.

* **Priority:** 100
* **Name:** rdp
* **Port:** 3389
* **Protocol:** TCP
* **Source:** *Your IP address*
* **Destination:** Any
* **Action:** Allow

2. Find the port number for the instance in the "Inbound NAT rules" blade of the Load Balancer.

3. Connect to the instance using RDP.
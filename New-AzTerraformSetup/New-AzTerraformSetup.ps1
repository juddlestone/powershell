
function New-AzTerraformSetup {
    <#
    .SYNOPSIS
    Creates a new Azure resource group, storage account, container, and managed identity to be used for Terraform state.

    .DESCRIPTION
    The function automates the creation of the resource group, storage account, managed identity. Whilst also creating a terraform container
    within the storage account to store the terraform state file. The function will also configure the necessary role assignment to allow the
    managed identity to access the storage account.

    .PARAMETER ResourceGroupName
    Specifies the name of the resource group to be created.

    .PARAMETER Location
    Specifies the Azure region where the resources will be created.

    .PARAMETER StorageAccountName
    Specifies the name of the storage account to be created.

    .PARAMETER ContainerName
    Specifies the name of the container to be created within the storage account.

    .PARAMETER IdentityName
    Specifies the name of the managed identity to be created.

    .PARAMETER Tags
    Specifies a hashtable of tags to be applied to the resources. This parameter is optional.

    .EXAMPLE
    New-AzTerraformSetup -ResourceGroupName "myResourceGroup" -Location "EastUS" -StorageAccountName "mystorageaccount" -ContainerName "mycontainer" -IdentityName "myidentity"

    #>
    param (
        [string]$ResourceGroupName,
        [string]$Location,
        [string]$StorageAccountName,
        [string]$ContainerName,
        [string]$IdentityName,
        [hashtable]$Tags = @{}
    )


    # Version
    $version = "v0.0.1"


    # Find The Maximum Length Of The Strings So The Seperator Can Be The Correct Length
    # Makes the intro message look nice :) 
    $maxLength = @(
        "Azure Terraform Setup Initialization",
        "Version: $version",
        "Resource Group Name: $ResourceGroupName",
        "Storage Account Name: $StorageAccountName",
        "Container Name: $ContainerName",
        "Identity Name: $IdentityName",
        "Location: $Location"
    ) | ForEach-Object { $_.Length } | Measure-Object -Maximum
    $lineLength = $maxLength.Maximum
    $separator = "-" * $lineLength


    # Intro Message
    # Just a nice to have
    Write-Host $separator -ForegroundColor Yellow
    Write-Host "Azure Terraform Setup Initialization" -ForegroundColor Green
    Write-Host "Version: $version" -ForegroundColor Green
    Write-Host $separator -ForegroundColor Yellow
    Write-Host "Resource Group Name: $ResourceGroupName" -ForegroundColor Green
    Write-Host "Storage Account Name: $StorageAccountName" -ForegroundColor Green
    Write-Host "Container Name: $ContainerName" -ForegroundColor Green
    Write-Host "Identity Name: $IdentityName" -ForegroundColor Green
    Write-Host "Location: $Location" -ForegroundColor Green
    Write-Host $separator -ForegroundColor Yellow


    # Check 'Az' Module Is Installed
    # Will need this to create the resources
    Write-Host "Checking 'Az' Module Is Installed..." -ForegroundColor Green
    $azModule = Get-InstalledModule -Name Az -ErrorAction SilentlyContinue
    if (-not $azModule) {

        Write-Error "Az module is not installed. Please install the module (Install-Module Az -AllowClobber) before running this script again. Exiting."
        return

    } else {

        Write-Host "- Check Passed! Version: $($azModule.Version)" -ForegroundColor Cyan

    }


    # Check Connectivity To Azure
    # Ensure we're connected to Azure before
    Write-Host "`nChecking Connectivity To Azure..." -ForegroundColor Green
    if (-not (Get-AzContext)) {

        Write-Error "Not connected to Azure. Please connect to Azure (Connect-AzAccount) before running this script again. Exiting."
        return

    } 
    else {

        $domainContext = (Get-AzContext).Account.Id.Split("@")[-1]
        $subscriptionname = (Get-AzContext).Subscription.Name
        Write-Host "- Check Passed!" -ForegroundColor Cyan
        Write-Host "- Domain: $domainContext" -ForegroundColor Cyan
        Write-Host "- Subscription: $subscriptionName" -ForegroundColor Cyan
        Write-Host "- Continue? (Press any key to continue)" -ForegroundColor Cyan -NoNewline
        Read-Host -Prompt " "

    }


    # Create Resource Group
    Write-Host "`nCreating Resource Group..." -ForegroundColor Green
    $resourceGroup = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue
    if (-not $resourceGroup) {

        try {
            $resourceGroup = New-AzResourceGroup -Name $ResourceGroupName -Location $Location -Tag $Tags

        } catch {
            Write-Error "Failed to create resource group: $_"
            return

        }
    } else {
        Write-Error "`nResource group '$ResourceGroupName' already exists!"
        return

    }
    Write-Host "- Success! Resource Group Created." -ForegroundColor Cyan


    # Create Storage Account, Checking the Name Availability Before Hand
    # This will store the terraform container
    Write-Host "`nChecking Storage Account Name Availability..." -ForegroundColor Green
    $storageAccountNameAvailability = (Get-AzStorageAccountNameAvailability -Name $StorageAccountName).NameAvailable
    if ($storageAccountNameAvailability) {
        Write-Host "- Check Passed! Storage Account Name Is Available!" -ForegroundColor Cyan

        try {

            Write-Host "`nCreating Storage Account..." -ForegroundColor Green
            $storageAccount = New-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName -Location $Location -SkuName Standard_LRS -Tag $Tags

        }
        catch {

            Write-Error "Failed to create storage account: $_"
            return

        }
    }
    else {

        Write-Error "Storage account name $StorageAccountName is not available"
        return

    }
    Write-Host "- Success! Storage Account Created." -ForegroundColor Cyan


    # Create Storage Container
    # This will store the terraform state file
    Write-Host "`nCreating Storage Container..." -ForegroundColor Green
    try {

        $container = New-AzStorageContainer -Name $ContainerName -Context $storageAccount.Context -Permission Off -ErrorAction Stop

    }
    catch {

        Write-Error "Failed to create storage container: $_"
        return

    }
    Write-Host "- Success! Storage Container Created." -ForegroundColor Cyan


    # Create User Assigned Identity
    # This will be used to authenticate to the storage account
    try {

        Write-Host "`nCreating User Assigned Identity..." -ForegroundColor Green
        $identity = New-AzUserAssignedIdentity -ResourceGroupName $ResourceGroupName -Name $IdentityName -Location $Location -Tag $Tags

    }
    catch {

        Write-Error "Failed to create user assigned identity: $_"
        return

    }
    Write-Host "- Success! User Assigned Identity Created." -ForegroundColor Cyan


    # Configuring Role Assignment
    # Give permission to the identity to access the storage account
    try {

        Write-Host "`nConfiguring Role Assignment..." -ForegroundColor Green
        $roleAssignment = New-AzRoleAssignment -ObjectId $identity.PrincipalId -RoleDefinitionName "Storage Blob Data Contributor" -Scope $storageAccount.Id -ErrorAction Stop

    }
    catch {

        Write-Error "Failed to configure role assignement. Do you have the correct permissions?: $_"
        return

    }
    Write-Host "- Success! Role Assignment Configured." -ForegroundColor Cyan


    # Output Setup Complete
    Write-Host "`nSetup Complete! Enjoy Terraforming!" -ForegroundColor Green
    Write-Host $separator -ForegroundColor Yellow


    # Deployment Object
    $deployment= [PSCustomObject]@{

        ManagedIdentityName = $identity.Name
        ManagedIdentityId = $identity.Id
        ResourceGroupName = $resourceGroup.ResourceGroupName
        ResourceGroupId = $resourceGroup.ResourceId
        StorageAccountName = $storageAccount.StorageAccountName
        StorageAccountId = $storageAccount.Id

    }

    
    # Return Deployment Object
    return $deployment
}
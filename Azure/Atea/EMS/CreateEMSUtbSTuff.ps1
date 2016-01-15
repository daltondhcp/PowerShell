[CmdletBinding(SupportsShouldProcess=$true)]
param (
    [switch]$ForceLogin,
    [switch]$DoItOverAgain,
    [switch]$Win10Fix
)
#Set-AzureRMVMExtension –ResourceGroupName “rg1” -Name "JsonADDomainExtension" -Publisher "Microsoft.Compute" -TypeHandlerVersion "1.0" -Settings '{ "Name" : "workgroup1", "User" : "domain\test", "Restart" : "false", "Options" : 1}' -VMName “testvm” -ProtectedSettings '{"password": "pass"}'

#Define variables and Uri's to scripts/assets
$RGName = "AteaEMS"
$Location = "North Europe"
$TemplateUri = "https://365lab.blob.core.windows.net/scripts/azuredeploy.json"
$FinalizeScript = "https://365lab.blob.core.windows.net/scripts/Finalize-AteaEMSVM.ps1"
$DSCAssetLocation = "https://threesixfivelab.blob.core.windows.net/scripts/"
Import-Module Azur* -Verbose:$false
#Verify Azure PowerShell version 
$AzureModule = Get-Module -ListAvailable AzureRM.Compute -verbose:$false
if ($Azuremodule.Version.Major -lt 1) {
    break "Your Azuremodule does not support Resource manager properly, please install the latest version"
}
#Verify azure connection, or prompt for login
$AzureSubScription = Get-AzureRmSubscription
if (-not($AzureSubScription) -or $ForceLogin) {
    Login-AzureRmAccount  
}
#Reset the entire environment if $DoItOverAgain switch has been used
if ($DoItOverAgain) {
    Write-Verbose "DoItOverAgain Switch was used, will remove all existing resources"
    Remove-AzureRmResourceGroup -Name $RGName -Force 
    Write-Verbose "Waiting additional 30 seconds after resource group removal..."
    Start-Sleep 30
}

#Check for resource group
$RGroup = Get-AzureRmResourceGroup -Name $RGName -Location $Location -ErrorAction Ignore -WarningAction Ignore

try {
    #Create resource group if not exists
    if (-not($RGroup)) {
        New-AzureRmResourceGroup -Name $RGName -Location $Location -Force -ErrorAction Stop
    }

    #Check if storage account exists , generate new if not.
    #Check if storage account exists , generate new if not.
    $StorageAccount = Get-AzureRmStorageAccount | Where-Object {$_.StorageAccountName -like "atea*"} -ErrorAction Ignore

    if ($StorageAccount) {
        $DNSName = $StorageAccount.StorageAccountName
        if ($Win10Fix) {
            Write-Verbose "Trying to start DC01..."
            Start-AzureRmVM -Name DC01 -ResourceGroupName $RGName 
            $blobName = "Microsoft.Compute/Images/vhds/template-osDisk.e00e29d5-eb33-4227-99a0-556c8e691bf3.vhd" 
            # Source Storage Account Information #
            $sourceStorageAccountName = "365lab"
            $sourceKey = "IEg+b7wPfW9I4nvPQa6g14kSOwBcnnyLxKiy8muDKHtUER+V0XlQcMDO4b7D/jy77yGxGj6UKANXh42vvKPOUA=="
            $sourceContext = New-AzureStorageContext –StorageAccountName $sourceStorageAccountName -StorageAccountKey $sourceKey  
            $sourceContainer = "system"

            # Destination Storage Account Information #
            $destinationStorageAccountName = (Get-AzureRmStorageAccount | Where-Object {$_.StorageAccountName -like "atea*"}).StorageAccountName
            $destinationKey = (Get-AzureRmStorageAccountKey -Name $destinationStorageAccountName -ResourceGroupName $RGName).Key1
            $destinationContext = New-AzureStorageContext –StorageAccountName $destinationStorageAccountName -StorageAccountKey $destinationKey  

            # Create the destination container #
            $destinationContainerName = "destinationvhds"
            New-AzureStorageContainer -Name $destinationContainerName -Context $destinationContext 

            # Copy the blob # 
            $blobCopy = Start-AzureStorageBlobCopy -DestContainer $destinationContainerName `
                                -DestContext $destinationContext `
                                -SrcBlob $blobName `
                                -Context $sourceContext `
                                -SrcContainer $sourceContainer
            while (($blobCopy | Get-AzureStorageBlobCopyState).Status -eq "Pending") {
                Start-Sleep -Seconds 30
                $blobCopy | Get-AzureStorageBlobCopyState
            }
        }
    } else {
        $DNSName = "{0}{1}" -f $rgname.ToLower(),[guid]::NewGuid().guid.split("-")[0]
        New-AzureRmStorageAccount -ResourceGroupName $RGName -Name $DNSName -Type Standard_LRS -Location $Location -Verbose
        Start-Sleep -Seconds 15
        $blobName = "Microsoft.Compute/Images/vhds/template-osDisk.e00e29d5-eb33-4227-99a0-556c8e691bf3.vhd" 
        # Source Storage Account Information #
        $sourceStorageAccountName = "365lab"
        $sourceKey = "IEg+b7wPfW9I4nvPQa6g14kSOwBcnnyLxKiy8muDKHtUER+V0XlQcMDO4b7D/jy77yGxGj6UKANXh42vvKPOUA=="
        $sourceContext = New-AzureStorageContext –StorageAccountName $sourceStorageAccountName -StorageAccountKey $sourceKey  
        $sourceContainer = "system"

        # Destination Storage Account Information #
        $destinationStorageAccountName = (Get-AzureRmStorageAccount | Where-Object {$_.StorageAccountName -like "atea*"}).StorageAccountName
        $destinationKey = (Get-AzureRmStorageAccountKey -Name $destinationStorageAccountName -ResourceGroupName $RGName).Key1
        $destinationContext = New-AzureStorageContext –StorageAccountName $destinationStorageAccountName -StorageAccountKey $destinationKey  

        # Create the destination container #
        $destinationContainerName = "destinationvhds"
        New-AzureStorageContainer -Name $destinationContainerName -Context $destinationContext 

        # Copy the blob # 
        $blobCopy = Start-AzureStorageBlobCopy -DestContainer $destinationContainerName `
                            -DestContext $destinationContext `
                            -SrcBlob $blobName `
                            -Context $sourceContext `
                            -SrcContainer $sourceContainer
        while (($blobCopy | Get-AzureStorageBlobCopyState).Status -eq "Pending") {
            Start-Sleep -Seconds 30
            $blobCopy | Get-AzureStorageBlobCopyState
        }

    }  



    #Create deployment from json Template
    $parameters = @{
                "PublicDNSName"="$DNSName"
                "NewStorageAccount"="$DNSName"
                "DOmainName"="corp.tp2b.com"
                "adminUserName"='sysadmin'
                "adminPassword"='Atea2016!'
                "assetLocation"=$DSCAssetLocation
    }
    Write-Verbose "Will start deployment $DNSName in $RGName ($Location)"
    $GroupDeploymentHt = @{
        Name = "AteaEMS"
        ResourceGroupName = "$RGName"
        #TemplateFile = "C:\Users\Johan\Desktop\Temp\azuredeploy.json"
        TemplateParameterObject = $parameters 
        TemplateUri = $TemplateUri
    }
    New-AzureRmResourceGroupDeployment @GroupDeploymentHt -Verbose -ErrorAction Stop 

    #Customize vm with custom scripts from finalization script
    $AzureVMs = Get-AzureRmVM 
    
    #Stop all VM's
    $AzureVMs | ForEach-Object -Process {
        Write-Verbose "Stopping vm $($_.Name)"
        $_ | Stop-AzureRmVM -Force -ErrorAction Stop
    } 
} catch {
    Write-Warning "An error occured. The script can safely be restared and will resume where it left off.`r`n$_"

} 
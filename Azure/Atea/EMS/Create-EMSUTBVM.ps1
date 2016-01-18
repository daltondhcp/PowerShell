[CmdletBinding(SupportsShouldProcess=$true)]
param (
    [switch]$ForceLogin,
    [switch]$DoItOverAgain,
    [switch]$DownloadWin10VHD
)
#Define variables and Uri's to scripts/assets
$RGName = 'AteaEMS'
$Location = 'North Europe'
$TemplateUri = 'https://raw.githubusercontent.com/daltondhcp/PowerShell/master/Azure/Atea/EMS/azuredeploy-ateaems.json'
$DSCAssetLocation = 'https://raw.githubusercontent.com/daltondhcp/PowerShell/master/Azure/Atea/EMS/'
$DomainName = 'corp.tp2b.com'
$adminUserName = 'sysadmin'
$adminPassword = 'Pa$$w0rd'

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
    $StorageAccount = Get-AzureRmStorageAccount | Where-Object {$_.StorageAccountName -like "atea*"} -ErrorAction Ignore

    if ($StorageAccount) {
        #If storage account with the prefix exist, use that.
        $DNSName = $StorageAccount.StorageAccountName
    } else {
        #Generate DNS name/storage account name if not exists based on the resource group name and a part of a guid
        $DNSName = "{0}{1}" -f $rgname.ToLower(),[guid]::NewGuid().guid.split("-")[0]
        #Create a storage account with the required properties
        New-AzureRmStorageAccount -ResourceGroupName $RGName `
                                  -Name $DNSName -Type Standard_LRS `
                                  -Location $Location
        #Download Windows 10 to storage account if that switch have been used
        if ($DownloadWin10VHD) {
            Start-Sleep -Seconds 15
            #region copy Windows 10 media from other storage account to the newly created. 
            #This is needed since Windows 10 SKU's only are available in MSDN subscriptions.
            $blobName = "Microsoft.Compute/Images/vhds/template-osDisk.e00e29d5-eb33-4227-99a0-556c8e691bf3.vhd" 
            # Source Storage Account Information with Windows 10 media
            $sourceStorageAccountName = "365lab"
            $sourceKey = ""
            $sourceContext = New-AzureStorageContext –StorageAccountName $sourceStorageAccountName -StorageAccountKey $sourceKey  
            $sourceContainer = "system"

            # Destination Storage Account Information 
            $destinationStorageAccountName = (Get-AzureRmStorageAccount | Where-Object {$_.StorageAccountName -like "atea*"}).StorageAccountName
            $destinationKey = (Get-AzureRmStorageAccountKey -Name $destinationStorageAccountName -ResourceGroupName $RGName).Key1
            $destinationContext = New-AzureStorageContext –StorageAccountName $destinationStorageAccountName -StorageAccountKey $destinationKey  

            # Create the destination container to store the VHD.
            $destinationContainerName = "destinationvhds"
            New-AzureStorageContainer -Name $destinationContainerName -Context $destinationContext 

            # Copy the blob from the source to the destination.
            $blobCopy = Start-AzureStorageBlobCopy -DestContainer $destinationContainerName `
                                -DestContext $destinationContext `
                                -SrcBlob $blobName `
                                -Context $sourceContext `
                                -SrcContainer $sourceContainer
        
            #Wait for the copy to complete before continue.
            while (($blobCopy | Get-AzureStorageBlobCopyState).Status -eq "Pending") {
                Start-Sleep -Seconds 30
                $blobCopy | Get-AzureStorageBlobCopyState
            }
        }
    }  

    #Create deployment from json Template
    $parameters = @{
                "PublicDNSName" = $DNSName
                "NewStorageAccount" = $DNSName
                "DomainName" = $DomainName
                "adminUserName" = $adminUserName
                "adminPassword" = $adminPassword
                "assetLocation" = $DSCAssetLocation
    }
    Write-Verbose "Will start deployment $DNSName in $RGName ($Location)"
    $GroupDeploymentHt = @{
        Name = "AteaEMS"
        ResourceGroupName = "$RGName"
        #TemplateFile = "C:\Users\Johan\Desktop\Temp\azuredeploy-ateaems.json"
        TemplateParameterObject = $parameters 
        TemplateUri = $TemplateUri
    }
    New-AzureRmResourceGroupDeployment @GroupDeploymentHt -ErrorAction Stop 

    $AzureVMs = Get-AzureRmVM 
    #Stop all VM's after deployment
    $AzureVMs | ForEach-Object -Process {
        Write-Verbose "Stopping vm $($_.Name)"
        $_ | Stop-AzureRmVM -Force -ErrorAction Stop
    } 
} catch {
    Write-Warning "An error occured. The script can safely be restarted and will resume where it left off.`r`n$_"

} 
<#
.SYNOPSIS
    A script to change the license type of an Azure Windows VM between Hybrid 
    Use and Standard Windows Licensing models.
.DESCRIPTION
    See the following Microsoft link for more details on the Hybrid use offer
    https://azure.microsoft.com/en-gb/pricing/hybrid-use-benefit/ 

    It's normally only possible to create a fresh VM and assign the hybrid use 
    benefit. This script works around that by deleting the original virtual
    machine configuration and then recreating the VM as a fresh machine and re
    attaching the original disks.

    It's highly likely that this script misses some edge cases so you should NOT
    run this in a production environment and should do your own testing.

    THIS MATERIAL IS PROVIDED AS IS, WITH ABSOLUTELY NO WARRANTY EXPRESSED
    OR IMPLIED.  ANY USE IS AT YOUR OWN RISK.
.NOTES
    File Name      : Set-AzureRmVmLicenseType.ps1
    Author         : Dave Hall
    Prerequisite   : PowerShell V5 (Tested with V5, may work in earlier)
                     AzureRM Powershell Module (Install-Module AzureRM) 
                        Tested with 4.0.2
    Copyright 2017 - Dave Hall
.LINK
    http://blog.superautomation.co.uk
.EXAMPLE
    .\Set-AzureRmVmLicenseType.PS1 -VmName "myHybridVm"" -LicenseType "Standard"
.EXAMPLE
    .\Set-AzureRmVmLicenseType.PS1 -VmName "myStandardVm"" -LicenseType "Hybrid"
#>

Param (
    [Parameter(Mandatory=$true)]
    $VmName, 

    [switch]
    $Force=$False,

    [ValidateSet("Hybrid","Standard")]
    [Parameter(Mandatory=$true)]
    [String]$LicenseType
)
$VM = Get-AzureRmVM -WarningAction SilentlyContinue | ? {$_.Name -eq $VMName}

## Perform prerequesite checks
if (!($VM) -or $VM.Count -gt 1) {
    Write-Error "Unable to find VM or VM name is ambiguous."
    Exit 1
}
if ($VM.StorageProfile.OsDisk.OsType -ne "Windows") {
    Write-Error "Virtual Machine must be running Windows"
    Exit 2
}
switch ($LicenseType) {
    "Hybrid"    {
        $NewLicenseString = "Windows_Server"
        if ($VM.LicenseType -eq "Windows_Server") {
            Write-Error "Virtual Machine is already using Hybrid Use license type" 
            Exit 3
        }
    }
    "Standard"    {
        $NewLicenseString = $Null
        if ($VM.LicenseType -ne "Windows_Server") {
            Write-Error "Virtual Machine is already using standard license type"
            Exit 3
        }
    }
}

#Copy the VM config out to a file
if (!(Test-Path ".\VM-Backups")) {
    $Null = New-Item -Path ".\VM-Backups" -ItemType "Directory"
}
Export-Clixml -Path ".\VM-Backups\$($VM.Name).Original.xml" -InputObject $VM

Write-Host "Changing License type on VM: " -NoNewLine
Write-Host $VM.Name -Foregroundcolor Yellow
Write-Host "New License Type: " -NoNewLine
Write-Host $LicenseType -Foregroundcolor Yellow
Write-Host "Current Virtual Machine State: " -NoNewLine
$VMState = $VM | Get-AzureRmVm -WarningAction SilentlyContinue -Status | 
            select Name, @{n="Status"; e={$_.Statuses[1].DisplayStatus}}
Write-Host $VMState.Status -Foregroundcolor Yellow

if ($VMState.Status -eq "VM Running") {
    #Stop the VM if force enabled
    if ($Force) {
        Write-Host "Stopping VM..."
        $Stopped = $VM | Stop-AzureRMVM -Force
    } else {
        #Show warning
        Write-Warning "VM is currently running, use -force to stop the VM"
        Break
    }
}

#Remove the VM config
Write-Host "Removing the VM configuration..."
$VM | Remove-AzureRmVm -Force

#Take a copy of the object so that LicenseType property is NULL
[Microsoft.Azure.Commands.Compute.Models.PSVirtualMachine]$NewVM = $VM | 
        Select * -ExcludeProperty LicenseType, ResourceGroupName, `
        DataDiskNames, NetworkInterfaceIds

#Remove disallowed settings
$osType = $VM.StorageProfile.OsDisk.OsType
$NewVM.StorageProfile.OsDisk.OsType = $Null
$NewVM.StorageProfile.ImageReference = $Null
$NewVM.OSProfile = $Null

#Old VM Information
$rgName = $VM.ResourceGroupName
$locName = $VM.Location
$osDiskUri = $VM.StorageProfile.OsDisk.Vhd.Uri
$diskName = $VM.StorageProfile.OsDisk.Name
$osDiskCaching = $VM.StorageProfile.OsDisk.Caching

#Set the OS disk to attach
$NewVM = Set-AzureRmVMOSDisk -VM $NewVM -VhdUri $osDiskUri -name $DiskName `
    -CreateOption attach -Windows -Caching $osDiskCaching 

#Attach data Disks
if ($VM.StorageProfile.DataDisks.count -gt 0) {
    Write-Host "Configure additional disks"
    $DataDisks = $VM.StorageProfile.DataDisks
    $NewVM.StorageProfile.DataDisks = $Null
    foreach ($DataDisk in $DataDisks) {
        $NewVM = Add-AzureRmVMDataDisk -VM $NewVM -VhdUri $DataDisk.Vhd.Uri `
            -Name $DataDisk.Name -CreateOption "Attach" `
            -Caching $DataDisk.Caching -DiskSizeInGB $DataDisk.DiskSizeInGB `
            -Lun $DataDisk.Lun
    }   
}

#If this isn't set the VM will default to Windows and get stuck in the "Updating" state
#Probably because -windows is set when adding the OS disk!
Write-Host "Setting VM OsType to $($osType)"
$NewVM.StorageProfile.OsDisk.OsType = $osType

$OldLicenseVM = $NewVM

#Set the new license type (or leave NULL)
if ($NewLicenseString) {
    Write-Host "Set License Type to Windows_Server"
    $NewVM.LicenseType = $NewLicenseString
} else {
    Write-Host "Set License Type to `$Null"
}

#Recreate the VM
Write-Host "Recreate the VM..."
Try {
    New-AzureRmVM -ResourceGroupName $rgName -Location $locName -VM $NewVM -WarningAction Ignore
} catch {
    Write-Warning "Failed to recreate the VM using the new license type, recreating with old settings..."
    New-AzureRmVM -ResourceGroupName $rgName -Location $locName -VM $OldLicenseVM -WarningAction Ignore
}

Switch ($VMState.Status) {
    "VM deallocated" {
        Write-Host "Stopping (deallocate) the VM."
        Get-AzureRmVM | Where-Object {$_.Name -eq $VM.Name} | Stop-AzureRmVm -Confirm:$False
    }
    "VM stopped" {
        Write-Host "Stopping (stay provisioned) the VM."
        Get-AzureRmVM | Where-Object {$_.Name -eq $VM.Name} | Stop-AzureRmVm -StayProvisioned -Confirm:$False
    }
}

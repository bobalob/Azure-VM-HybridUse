# ARM-HybridUse
Scripts to get and toggle Azure Hybrid Use Benefit / Standard licensing - http://blog.superautomation.co.uk/2017/07/convert-azure-windows-virtual-machine.html

__WARNING__ - The Set-AzureRmVmLicenseType.PS1 script has to __destroy__ your existing VM and recreate a new VM based on the old machine spec. __DO NOT__ use this on a machine that you have not backed up. 

###Get a list of VMs and their current license type - Windows\_Server is the hybrid use license type.
    Get-AzureRmVmLicenseType.PS1
	
###Set a VM to hybrid use benefit
    Set-AzureRmVmLicenseType.PS1 -VmName testvm1 -LicenseType Hybrid -Force
	
###Set a VM to regular licensing
    Set-AzureRmVmLicenseType.PS1 -VmName testvm1 -LicenseType Standard -Force

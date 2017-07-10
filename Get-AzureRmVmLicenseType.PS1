Param(
    $VMName
)

$VMTab = Get-AzureRmVm -Status | Select-Object -Property ResourceGroupName, LicenseType, `
    @{Name="OsType"; Expression={$_.StorageProfile.OsDisk.OsType}}, `
    Name, Location, PowerState, @{Name="VmSize"; Expression={$_.HardwareProfile.VmSize}}

if ($VMName) {
    $VMTab | Where-Object {$_.Name -eq $VMName} | Format-Table -AutoSize
} else {
    $VMTab | Format-Table -AutoSize
}

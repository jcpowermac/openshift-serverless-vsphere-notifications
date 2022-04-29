#!/bin/pwsh
. /var/run/config/vcenter/variables.ps1

Set-PowerCLIConfiguration -InvalidCertificateAction:Ignore -Confirm:$false | Out-Null
$cihash = ConvertFrom-Json -InputObject $ci -AsHashtable
foreach ($key in $cihash.Keys) {
    $cihash[$key].vcenter
    try {
        Connect-VIServer -Server $Env:VCENTER_URI -Credential (Import-Clixml $cihash[$key].secret) | Out-Null
        Get-VM
        Get-Datastore -Name $cihash[$key].datastore
        Get-Datacenter -Name $cihash[$key].datacenter
        Get-Cluster -Name $cihash[$key].datacenter
    }
    catch {
        Get-Error
        exit 1
    }
    finally {
        #Disconnect-CisServer -Server * -Force:$true -Confirm:$false
        Disconnect-VIServer -Server * -Force:$true -Confirm:$false
    }
}

exit 0

#!/bin/pwsh
. .\variables.ps1

try {

    $cihash = ConvertFrom-Json -InputObject $ci -AsHashtable
    foreach ($key in $cihash.Keys) {
        $cihash[$key].vcenter

#    Set-PowerCLIConfiguration -InvalidCertificateAction:Ignore -Confirm:$false | Out-Null
#    Connect-VIServer -Server $Env:VCENTER_URI -Credential (Import-Clixml $Env:VCENTER_SECRET_PATH) | Out-Null
    }
}
catch {
    Get-Error
    exit 1
}
finally {
    #Disconnect-CisServer -Server * -Force:$true -Confirm:$false
    #Disconnect-VIServer -Server * -Force:$true -Confirm:$false
}

exit 0

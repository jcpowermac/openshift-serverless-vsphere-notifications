#!/bin/pwsh
. /var/run/config/vcenter/variables.ps1

Set-PowerCLIConfiguration -InvalidCertificateAction:Ignore -Confirm:$false | Out-Null
$cihash = ConvertFrom-Json -InputObject $ci -AsHashtable
$slackMessage = @"
:fire: debug folder
vcenter: {0}
VM(s): {1}
"@

foreach ($key in $cihash.Keys) {
    try {
        Connect-VIServer -Server $cihash[$key].vcenter -Credential (Import-Clixml $cihash[$key].secret) | Out-Null
        Send-SlackMessage -Uri $Env:SLACK_WEBHOOK_URI -Text ($slackMessage -f $cihash[$key].vcenter)

        $debugVirtualMachines = @(Get-VM -Location (Get-Folder debug) | Select-Object -ExpandProperty Name)

        if($debugVirtualMachines.Count -gt 0) {
            $joinedVirtualMachines = $debugVirtualMachines -join ','
            Send-SlackMessage -Uri $Env:SLACK_WEBHOOK_URI -Text ($slackMessage -f $cihash[$key].vcenter, $joinedVirtualMachines)
        }
    }
    catch {
        Get-Error
    }
    finally {
        Disconnect-VIServer -Server * -Force:$true -Confirm:$false
    }
}

exit 0

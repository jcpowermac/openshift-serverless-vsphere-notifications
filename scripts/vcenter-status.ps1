#!/bin/pwsh

. /var/run/config/vcenter/variables.ps1

Set-PowerCLIConfiguration -InvalidCertificateAction:Ignore -Confirm:$false | Out-Null

$cihash = ConvertFrom-Json -InputObject $ci -AsHashtable

$slackMessage = @"
vCenter Status
vcenter: {0}
VM Count (soap): {1}
Tag Count (rest): {2}
"@

$errmessage = @"
vCenter: {0}
Error: {1}
"@

foreach ($key in $cihash.Keys) {
    $cihash[$key].vcenter
    try {

        Connect-VIServer -Server $cihash[$key].vcenter -Credential (Import-Clixml $cihash[$key].secret) | Out-Null

        $vm = Get-VM
        $tag = Get-Tag


        $vm.Count
        $tag.Count

        # we don't need messages unless its broke...
        #Send-SlackMessage -Uri $Env:SLACK_WEBHOOK_URI -Text ($slackMessage -f $cihash[$key].vcenter, $vm.Count, $tag.Count)

    }
    catch {
        $caught = Get-Error
        $errStr = $caught.ToString()

        $caught


        Send-SlackMessage -Uri $Env:SLACK_WEBHOOK_URI -Text ($errmessage -f $cihash[$key].vcenter, $errStr)
        exit 1
    }
    finally {
        Disconnect-VIServer -Server * -Force:$true -Confirm:$false
    }
}

exit 0

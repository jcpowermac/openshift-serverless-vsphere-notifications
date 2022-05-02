#!/bin/pwsh
. /var/run/config/vcenter/variables.ps1

Set-PowerCLIConfiguration -InvalidCertificateAction:Ignore -Confirm:$false | Out-Null
$cihash = ConvertFrom-Json -InputObject $ci -AsHashtable
$slackMessage = @"
Removing storage policies
vcenter: {0}
storage policies: {1}
"@

$deleteday = (Get-Date).AddDays(-4)
foreach ($key in $cihash.Keys) {
    try {
        $cihash[$key].vcenter
        $cihash[$key].datacenter
        $cihash[$key].cluster
        $cihash[$key].datastore

        Connect-VIServer -Server $cihash[$key].vcenter -Credential (Import-Clixml $cihash[$key].secret) | Out-Null

        $storagePolicies = @(Get-SpbmStoragePolicy | Where-Object -Property Name -Like "*ci*" | Where-Object -Property CreationTime -LT $deleteday)
        Send-SlackMessage -Uri $Env:SLACK_WEBHOOK_URI -Text ($slackMessage -f $cihash[$key].vcenter, $storagePolicies.Count)

        foreach ($policy in $storagePolicies) {
            Remove-SpbmStoragePolicy -StoragePolicy $policy -Confirm:$false -ErrorAction Continue
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

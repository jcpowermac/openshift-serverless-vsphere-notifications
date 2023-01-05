#!/bin/pwsh
. /var/run/config/vcenter/variables.ps1

Set-PowerCLIConfiguration -InvalidCertificateAction:Ignore -Confirm:$false | Out-Null
$cihash = ConvertFrom-Json -InputObject $ci -AsHashtable
$slackMessage = @"
Removing vsan file shares
vcenter: {0}
file shares: {1}
"@

foreach ($key in $cihash.Keys) {
    try {
        $cihash[$key].vcenter
        $cihash[$key].datacenter
        $cihash[$key].cluster
        $cihash[$key].datastore

        Connect-VIServer -Server $cihash[$key].vcenter -Credential (Import-Clixml $cihash[$key].secret) | Out-Null

        $vsanFileShares = Get-VsanFileShare

        Send-SlackMessage -Uri $Env:SLACK_WEBHOOK_URI -Text ($slackMessage -f $cihash[$key].vcenter, $vsanFileShares.Count)


        foreach ($fs in $vsanFileShares) {
            $clusterId = ($fs.StoragePolicy.Name -split "openshift-storage-policy-")[1]
            if(-not($clusterId)) {
                $clusterInventory = Get-Inventory -Name $clusterId -ErrorAction Continue
                Write-Host $clusterId

                if ($clusterInventory.Count -eq 0) {
                    Write-Host "Removing vSan File share: $($fs.Id)"
                    $fs | Remove-VsanFileShare -Confirm:$false -Force:$true
                }
                else {
                    Write-Host "not deleting: $($clusterInventory)"
                }
            }
        }
    }
    catch {
        $caught = Get-Error
        $errStr = $caught.ToString()
        $caught
        Send-SlackMessage -Uri $Env:SLACK_WEBHOOK_URI -Text $errStr
    }
    finally {
        Disconnect-VIServer -Server * -Force:$true -Confirm:$false
    }
}

exit 0

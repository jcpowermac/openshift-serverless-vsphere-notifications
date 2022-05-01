#!/bin/pwsh

. /var/run/config/vcenter/variables.ps1

Set-PowerCLIConfiguration -InvalidCertificateAction:Ignore -Confirm:$false | Out-Null

$cihash = ConvertFrom-Json -InputObject $ci -AsHashtable

$slackMessage = @"
Removing resource pools(s)
vcenter: {0}
rp: {1}
"@

foreach ($key in $cihash.Keys) {
    $cihash[$key].vcenter
    try {

        Connect-VIServer -Server $cihash[$key].vcenter -Credential (Import-Clixml $cihash[$key].secret) | Out-Null

        $resourcePools = @(Get-ResourcePool | Where-Object { $_.Name -match '^ci*|^qeci*' })
        Send-SlackMessage -Uri $Env:SLACK_WEBHOOK_URI -Text ($slackMessage -f $cihash[$key].vcenter, $resourcePools.Count)

        foreach ($rp in $resourcePools) {
            [array]$resourcePoolVirtualMachines = $rp | Get-VM
            if ($resourcePoolVirtualMachines.Length -eq 0) {
                Write-Host "Remove RP: $($rp.Name)"
                Remove-ResourcePool -ResourcePool $rp -Confirm:$false -ErrorAction Continue
            }
        }
    }
    catch {
        Get-Error
        exit 1
    }
    finally {
        Disconnect-VIServer -Server * -Force:$true -Confirm:$false
    }
}

exit 0

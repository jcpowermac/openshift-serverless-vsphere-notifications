#!/bin/pwsh
. /var/run/config/vcenter/variables.ps1

Set-PowerCLIConfiguration -InvalidCertificateAction:Ignore -Confirm:$false | Out-Null
$cihash = ConvertFrom-Json -InputObject $ci -AsHashtable
$slackMessage = @"
vcenter: {0}
esxi alerts: {1}
"@

foreach ($key in $cihash.Keys) {
    $slackMessageEsxiAlerts = @()
    try {
        $cihash[$key].vcenter
        $cihash[$key].datacenter
        $cihash[$key].cluster
        $cihash[$key].datastore

        Connect-VIServer -Server $cihash[$key].vcenter -Credential (Import-Clixml $cihash[$key].secret) | Out-Null


        $esxi = Get-VMHost 

        foreach ($e in $esxi) {
            $hostview = $e | Get-View
            $health = Get-View $hostView.ConfigManager.HealthStatusSystem
            $systemHealthInfo = $health.Runtime.SystemHealthInfo
            ForEach ($sensor in $systemHealthInfo.NumericSensorInfo) {
                if($sensor.HealthState.Key -ne "green") {
                    Write-Host $sensor.Name
                    $slackMessageEsxiAlerts += "$($e.Name) $($sensor.Name)"
                }
            }
        }        
        
        if ($slackMessageEsxiAlerts.Count -gt 0 ) {
            $esxiMessage =  $slackMessageEsxiAlerts -join ","
            Send-SlackMessage -Uri $Env:SLACK_WEBHOOK_URI -Text ($slackMessage -f $cihash[$key].vcenter,$esxiMessage)
        }

    }
    catch {
        $caught = Get-Error
        $errStr = $caught.ToString()

        $caught

        Send-SlackMessage -Uri $Env:SLACK_WEBHOOK_URI -Text $errStr
        exit 1
    }
    finally {
        Disconnect-VIServer -Server * -Force:$true -Confirm:$false
    }
}

exit 0

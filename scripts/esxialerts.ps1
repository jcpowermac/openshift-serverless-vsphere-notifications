#!/bin/pwsh
. /var/run/config/vcenter/variables.ps1

Set-PowerCLIConfiguration -InvalidCertificateAction:Ignore -Confirm:$false | Out-Null
$cihash = ConvertFrom-Json -InputObject $ci -AsHashtable

# Function to send formatted Slack message
function Send-FormattedSlackMessage {
    param(
        [string]$Uri,
        [hashtable]$AlertData
    )
    
    $totalAlerts = 0
    $vcenterCount = 0
    
    foreach ($vc in $AlertData.Keys) {
        $totalAlerts += $AlertData[$vc].Count
        if ($AlertData[$vc].Count -gt 0) { $vcenterCount++ }
    }
    
    if ($totalAlerts -eq 0) {
        $message = ":white_check_mark: *ESXi Health Status - All Clear*`n"
        $message += "No ESXi health issues detected across all vCenters"
    } else {
        $message = ":warning: *ESXi Health Status - Active Alerts*`n"
        $message += "Total Alerts: *$totalAlerts* | vCenters with Issues: *$vcenterCount*`n`n"
        $message += "*Alerts by vCenter:*`n"
        
        foreach ($vc in $AlertData.Keys | Sort-Object) {
            if ($AlertData[$vc].Count -gt 0) {
                $message += "`n*$vc*:"
                foreach ($alert in $AlertData[$vc]) {
                    $message += "`n  • $alert"
                }
            }
        }
    }
    
    Send-SlackMessage -Uri $Uri -Text $message
}

$allAlertData = @{}  # Store alerts per vCenter

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
        
        # Store alerts for this vCenter
        if ($slackMessageEsxiAlerts.Count -gt 0) {
            $allAlertData[$cihash[$key].vcenter] = $slackMessageEsxiAlerts
        }

    }
    catch {
        $caught = Get-Error
        $errStr = $caught.ToString()

        $caught

        Send-SlackMessage -Uri $Env:SLACK_WEBHOOK_URI -Text ":x: *Error in ESXi Alerts script for $($cihash[$key].vcenter):*`n$errStr"
        exit 1
    }
    finally {
        Disconnect-VIServer -Server * -Force:$true -Confirm:$false
    }
}

# Send consolidated message for all vCenters
if ($allAlertData.Count -gt 0) {
    Send-FormattedSlackMessage -Uri $Env:SLACK_WEBHOOK_URI -AlertData $allAlertData
} else {
    # Send "all clear" message if no alerts found
    Send-FormattedSlackMessage -Uri $Env:SLACK_WEBHOOK_URI -AlertData @{}
}

exit 0

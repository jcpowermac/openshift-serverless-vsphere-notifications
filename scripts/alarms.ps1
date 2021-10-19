#!/bin/pwsh

Set-PowerCLIConfiguration -InvalidCertificateAction:Ignore -Confirm:$false

Connect-VIServer -Server $Env:VCENTER_URI -Credential (Import-Clixml $Env:VCENTER_SECRET_PATH)

$AlarmStates = (Get-Datacenter).ExtensionData.TriggeredAlarmState

foreach ($as in $AlarmStates) {
    $alarm = Get-View -Id $as.Alarm
    $entity = Get-View -Id $as.Entity

    if($as.OverallStatus -eq "red"){
        Send-SlackMessage -Uri $Env:SLACK_WEBHOOK_URI -Text ":fire: $($entity.Name): $($alarm.Info.Name)"
    }
    # To lower the amount of alerts run only every 8 hours
    if(((get-date -Format HH) % 8) -eq 0) {
        if($as.OverallStatus -eq "yellow"){
            Send-SlackMessage -Uri $Env:SLACK_WEBHOOK_URI -Text "$($entity.Name): $($alarm.Info.Name)"
        }
    }
}

Disconnect-VIServer -Server * -Force:$true -Confirm:$false

#!/bin/pwsh

Set-PowerCLIConfiguration -InvalidCertificateAction:Ignore -Confirm:$false

Connect-VIServer -Server $Env:VCENTER_URI -Credential (Import-Clixml $Env:VCENTER_SECRET_PATH)

$AlarmStates = (Get-Datacenter).ExtensionData.TriggeredAlarmState

foreach ($as in $AlarmStates) {
    $alarm = Get-View -Id $as.Alarm

    if($as.OverallStatus -eq "red"){
        Send-SlackMessage -Uri $Env:SLACK_WEBHOOK_URI -Text " :fire: $($alarm.Info.Name)"
    }
}

Disconnect-VIServer -Server * -Force:$true -Confirm:$false

#!/bin/pwsh

try {

    $header = $false
    Set-PowerCLIConfiguration -InvalidCertificateAction:Ignore -Confirm:$false | Out-Null
    Connect-VIServer -Server $Env:VCENTER_URI -Credential (Import-Clixml $Env:VCENTER_SECRET_PATH) | Out-Null

    $AlarmStates = (Get-Datacenter).ExtensionData.TriggeredAlarmState


    foreach ($as in $AlarmStates) {
        $alarm = Get-View -Id $as.Alarm
        $entity = Get-View -Id $as.Entity

        if ($as.OverallStatus -eq "red") {
            if (!($header)) {
                Send-SlackMessage -Uri $Env:SLACK_WEBHOOK_URI -Text "***** Alarms: $($Env:VCENTER_URI) *****"
                $header = $true
            }
            Send-SlackMessage -Uri $Env:SLACK_WEBHOOK_URI -Text ":fire: $($entity.Name): $($alarm.Info.Name)"
        }
        # To lower the amount of alerts run only every 8 hours
        if (((Get-Date -Format HH) % 8) -eq 0) {
            if ($as.OverallStatus -eq "yellow") {
                if (!($header)) {
                    Send-SlackMessage -Uri $Env:SLACK_WEBHOOK_URI -Text "***** Alarms: $($Env:VCENTER_URI) *****"
                    $header = $true
                }
                Send-SlackMessage -Uri $Env:SLACK_WEBHOOK_URI -Text "$($entity.Name): $($alarm.Info.Name)"
            }
        }
    }
    Connect-CisServer -Server $Env:VCENTER_URI -Credential (Import-Clixml $Env:VCENTER_SECRET_PATH) | Out-Null
    if ((Invoke-GetHealthSystem) -ne "green") {
        Send-SlackMessage -Uri $Env:SLACK_WEBHOOK_URI -Text ":fire: VCSA General Health: $($Env:VCENTER_URI)"
    }
    if ((Invoke-GetHealthStorage) -ne "green") {
        Send-SlackMessage -Uri $Env:SLACK_WEBHOOK_URI -Text ":fire: VCSA Storage Health: $($Env:VCENTER_URI)"
    }
}
catch {
    Get-Error
    exit 1
}
finally {
    Disconnect-CisServer -Server * -Force:$true -Confirm:$false
    Disconnect-VIServer -Server * -Force:$true -Confirm:$false
}

exit 0

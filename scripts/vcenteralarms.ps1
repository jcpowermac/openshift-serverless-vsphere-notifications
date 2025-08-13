#!/bin/pwsh
. /var/run/config/vcenter/variables.ps1

Set-PowerCLIConfiguration -InvalidCertificateAction:Ignore -Confirm:$false | Out-Null
$cihash = ConvertFrom-Json -InputObject $ci -AsHashtable
$slackMessage = @"
vcenter: {0}
vcenter alarms: {1}
"@

foreach ($key in $cihash.Keys) {
    $slackMessageVcAlarms = @()
    try {
        $cihash[$key].vcenter
        $cihash[$key].datacenter
        $cihash[$key].cluster
        $cihash[$key].datastore

        Connect-VIServer -Server $cihash[$key].vcenter -Credential (Import-Clixml $cihash[$key].secret) | Out-Null

        # Method 1: Get triggered alarm states from datacenter
        try {
            $datacenter = Get-Datacenter -Name $cihash[$key].datacenter
            if ($datacenter) {
                $triggeredAlarmStates = $datacenter.ExtensionData.TriggeredAlarmState
                
                foreach ($alarmState in $triggeredAlarmStates) {
                    $alarm = Get-View -Id $alarmState.Alarm
                    $entity = Get-View -Id $alarmState.Entity
                    
                    $entityName = if ($entity) { $entity.Name } else { "Unknown" }
                    $alarmName = if ($alarm) { $alarm.Info.Name } else { "Unknown Alarm" }
                    
                    if ($alarmState.OverallStatus -eq "red") {
                        $slackMessageVcAlarms += ":fire: CRITICAL: $alarmName on $entityName"
                    } elseif ($alarmState.OverallStatus -eq "yellow") {
                        $slackMessageVcAlarms += ":warning: WARNING: $alarmName on $entityName"
                    }
                }
            }
        }
        catch {
            Write-Host "Could not get datacenter alarm states: $($_.Exception.Message)"
        }

        # Method 2: Get all active alarms using Get-Alarm
        try {
            $activeAlarms = Get-Alarm | Where-Object { $_.OverallStatus -ne "Green" }
            
            foreach ($alarm in $activeAlarms) {
                $entityName = if ($alarm.Entity) { $alarm.Entity.Name } else { "Unknown" }
                $status = $alarm.OverallStatus
                $alarmName = $alarm.Name
                
                if ($status -eq "Red") {
                    $slackMessageVcAlarms += ":fire: CRITICAL: $alarmName on $entityName"
                } elseif ($status -eq "Yellow") {
                    $slackMessageVcAlarms += ":warning: WARNING: $alarmName on $entityName"
                }
                
                if ($alarm.Description) {
                    $slackMessageVcAlarms += "  Description: $($alarm.Description)"
                }
            }
        }
        catch {
            Write-Host "Could not get active alarms: $($_.Exception.Message)"
        }

        # Method 3: Check vCenter health using CIS API
        try {
            Connect-CisServer -Server $cihash[$key].vcenter -Credential (Import-Clixml $cihash[$key].secret) | Out-Null
            
            # Check general vCenter health
            $generalHealth = Invoke-GetHealthSystem
            if ($generalHealth -ne "green") {
                $slackMessageVcAlarms += ":fire: VCSA General Health: $generalHealth"
            }
            
            # Check vCenter storage health
            $storageHealth = Invoke-GetHealthStorage
            if ($storageHealth -ne "green") {
                $slackMessageVcAlarms += ":fire: VCSA Storage Health: $storageHealth"
            }
            
            Disconnect-CisServer -Server * -Force:$true -Confirm:$false
        }
        catch {
            Write-Host "Could not check vCenter health: $($_.Exception.Message)"
        }

        # Method 4: Check specific system alarms
        try {
            $systemAlarms = Get-Alarm | Where-Object { 
                $_.OverallStatus -ne "Green" -and 
                ($_.Name -like "*system*" -or $_.Name -like "*vcenter*" -or $_.Name -like "*critical*" -or $_.Name -like "*storage*" -or $_.Name -like "*network*")
            }
            
            foreach ($sysAlarm in $systemAlarms) {
                $entityName = if ($sysAlarm.Entity) { $sysAlarm.Entity.Name } else { "System" }
                $status = $sysAlarm.OverallStatus
                $alarmName = $sysAlarm.Name
                
                if ($status -eq "Red") {
                    $slackMessageVcAlarms += ":fire: SYSTEM CRITICAL: $alarmName on $entityName"
                } elseif ($status -eq "Yellow") {
                    $slackMessageVcAlarms += ":warning: SYSTEM WARNING: $alarmName on $entityName"
                }
            }
        }
        catch {
            Write-Host "Could not check system alarms: $($_.Exception.Message)"
        }
        
        if ($slackMessageVcAlarms.Count -gt 0 ) {
            $vcAlarmMessage = $slackMessageVcAlarms -join "`n"
            Send-SlackMessage -Uri $Env:SLACK_WEBHOOK_URI -Text ($slackMessage -f $cihash[$key].vcenter, $vcAlarmMessage)
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

#!/bin/pwsh
. /var/run/config/vcenter/variables.ps1

Set-PowerCLIConfiguration -InvalidCertificateAction:Ignore -Confirm:$false | Out-Null
$cihash = ConvertFrom-Json -InputObject $ci -AsHashtable

# Function to send formatted Slack message
function Send-FormattedSlackMessage {
    param(
        [string]$Uri,
        [hashtable]$AlarmData
    )
    
    $totalAlarms = 0
    $criticalCount = 0
    $warningCount = 0
    
    foreach ($vc in $AlarmData.Keys) {
        $totalAlarms += $AlarmData[$vc].Count
        foreach ($alarm in $AlarmData[$vc]) {
            if ($alarm -like "*:fire:*") { $criticalCount++ }
            if ($alarm -like "*:warning:*") { $warningCount++ }
        }
    }
    
    if ($totalAlarms -eq 0) {
        $message = @"
:white_check_mark: *vCenter Health Status - All Clear*
No active alarms detected across all vCenters
"@
    } else {
        $message = @"
:warning: *vCenter Health Status - Active Alarms*
Total Alarms: *$totalAlarms* | Critical: *$criticalCount* | Warning: *$warningCount*

*Alarms by vCenter:*
"@
        
        foreach ($vc in $AlarmData.Keys | Sort-Object) {
            if ($AlarmData[$vc].Count -gt 0) {
                $message += "`n*$vc*:"
                foreach ($alarm in $AlarmData[$vc]) {
                    $message += "`n  $alarm"
                }
            }
        }
    }
    
    Send-SlackMessage -Uri $Uri -Text $message
}

$allAlarmData = @{}  # Store alarms per vCenter

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
        
        # Store alarms for this vCenter
        if ($slackMessageVcAlarms.Count -gt 0) {
            $allAlarmData[$cihash[$key].vcenter] = $slackMessageVcAlarms
        }

    }
    catch {
        $caught = Get-Error
        $errStr = $caught.ToString()

        $caught

        Send-SlackMessage -Uri $Env:SLACK_WEBHOOK_URI -Text ":x: *Error in vCenter Alarms script for $($cihash[$key].vcenter):*`n$errStr"
        exit 1
    }
    finally {
        Disconnect-VIServer -Server * -Force:$true -Confirm:$false
    }
}

# Send consolidated message for all vCenters
if ($allAlarmData.Count -gt 0) {
    Send-FormattedSlackMessage -Uri $Env:SLACK_WEBHOOK_URI -AlarmData $allAlarmData
} else {
    # Send "all clear" message if no alarms found
    Send-FormattedSlackMessage -Uri $Env:SLACK_WEBHOOK_URI -AlarmData @{}
}

exit 0

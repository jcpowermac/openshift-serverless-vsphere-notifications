#!/bin/pwsh

Connect-VIServer -Server $Env:VCENTER_URI -Credential (Import-Clixml $Env:VCENTER_SECRET_PATH)

$hosts = Get-VMHost

foreach($item in $hosts) {
    $percentage = ($item.CpuUsageMhz / $item.CpuTotalMhz).tostring("P")

    if($percentage -ge 90) {
        Send-SlackMessage -Uri $Env:SLACK_WEBHOOK_URI -Text ":fire: Host: $($item.Name), CPU: $($percentage)%"
    }
    elseif( $percentage -ge 80) {
        Send-SlackMessage -Uri $Env:SLACK_WEBHOOK_URI -Text ":mag: Host: $($item.Name), CPU: $($percentage)%"
    }
    else {
        Write-Host "Host is ok"
    }
}

#!/bin/pwsh

Connect-VIServer -Server $Env:VCENTER_URI -Credential (Import-Clixml $Env:VCENTER_SECRET_PATH)

$hosts = Get-VMHost

$message = ""
$ClusterCpuTotalMhz = 0
$ClusterCpuUsageMhz = 0

foreach($item in $hosts) {
    $ClusterCpuTotalMhz += $item.CpuTotalMhz
    $ClusterCpuUsageMhz += $item.CpuUsageMhz

    $percentage = ($item.CpuUsageMhz / $item.CpuTotalMhz).tostring("P")

    if($percentage -ge 90) {
        $message += " [:fire: Host: $($item.Name), CPU: $($percentage)] "
    }
    elseif( $percentage -ge 80) {
        $message += " [Host: $($item.Name), CPU: $($percentage)] "
    }
    Write-Host "Host: $($item.Name), CPU: $($percentage)"
}

$ClusterPercentage = ($ClusterCpuUsageMhz / $ClusterCpuTotalMhz).toString("P")

Write-Host "Cluster CPU: $($ClusterPercentage)"

if($ClusterPercentage -ge 80) {
    $message += " *Cluster CPU: $($ClusterPercentage)*"
    Send-SlackMessage -Uri $Env:SLACK_WEBHOOK_URI -Text $message
}

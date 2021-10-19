#!/bin/pwsh

Set-PowerCLIConfiguration -InvalidCertificateAction:Ignore -Confirm:$false

Connect-VIServer -Server $Env:VCENTER_URI -Credential (Import-Clixml $Env:VCENTER_SECRET_PATH)

$hosts = Get-VMHost

$message = ""
$ClusterCpuTotalMhz = 0
$ClusterCpuUsageMhz = 0

$fire = $false

foreach($item in $hosts) {
    $ClusterCpuTotalMhz += $item.CpuTotalMhz
    $ClusterCpuUsageMhz += $item.CpuUsageMhz

    $avgcpu = ($item.CpuUsageMhz / $item.CpuTotalMhz)
    $percentage = $avgcpu.toString("P")

    if($avgcpu -ge .85) {
        $message += " [:fire: Host: $($item.Name), CPU: $($percentage)] "
        $fire = $true
    }
    elseif($avgcpu -ge .75) {
        $message += " [Host: $($item.Name), CPU: $($percentage)] "
    }
    Write-Host "Host: $($item.Name), CPU: $($percentage)"
}

$ClusterPercentage = ($ClusterCpuUsageMhz / $ClusterCpuTotalMhz).toString("P")

Write-Host "Cluster CPU: $($ClusterPercentage)"

if($fire) {
    $message += " *Cluster CPU: $($ClusterPercentage)*"
    Send-SlackMessage -Uri $Env:SLACK_WEBHOOK_URI -Text $message
}

Disconnect-VIServer -Server * -Force:$true -Confirm:$false

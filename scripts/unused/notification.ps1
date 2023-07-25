#!/bin/pwsh


try {

    $debugVirtualMachines = @()

    Set-PowerCLIConfiguration -InvalidCertificateAction:Ignore -Confirm:$false | Out-Null

    Connect-VIServer -Server $Env:VCENTER_URI -Credential (Import-Clixml $Env:VCENTER_SECRET_PATH) | Out-Null

    $hosts = Get-VMHost

    $message = ""
    $ClusterCpuTotalMhz = 0
    $ClusterCpuUsageMhz = 0

    $fire = $false

    foreach ($item in $hosts) {
        $ClusterCpuTotalMhz += $item.CpuTotalMhz
        $ClusterCpuUsageMhz += $item.CpuUsageMhz

        $avgcpu = ($item.CpuUsageMhz / $item.CpuTotalMhz)
        $percentage = $avgcpu.toString("P")

        if ($avgcpu -ge .85) {
            $message += " [:fire: Host: $($item.Name), CPU: $($percentage)] "
            $fire = $true
        }
        elseif ($avgcpu -ge .75) {
            $message += " [Host: $($item.Name), CPU: $($percentage)] "
        }
        Write-Host "Host: $($item.Name), CPU: $($percentage)"
    }

    $ClusterPercentage = ($ClusterCpuUsageMhz / $ClusterCpuTotalMhz).toString("P")

    Write-Host "Cluster CPU: $($ClusterPercentage)"

    if ($fire) {
        $message += " *Cluster CPU: $($ClusterPercentage)*"
        Send-SlackMessage -Uri $Env:SLACK_WEBHOOK_URI -Text $message
    }

    # CI has moved virtual machines to the debug folder we better take a look
    $debugVirtualMachines = @(Get-VM -Location (Get-Folder debug) | Select-Object -ExpandProperty Name)

    if($debugVirtualMachines.Count -gt 0) {
        $debugVMSlackMsg = ":fire: VMs in debug folder: $($debugVirtualMachines -join ',')"
        Send-SlackMessage -Uri $Env:SLACK_WEBHOOK_URI -Text $debugVMSlackMsg
    }
}
catch {
    Get-Error
    exit 1
}
finally {
    Disconnect-VIServer -Server * -Force:$true -Confirm:$false
}

exit 0

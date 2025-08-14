#!/bin/pwsh

. /var/run/config/vcenter/variables.ps1

Set-PowerCLIConfiguration -InvalidCertificateAction:Ignore -Confirm:$false | Out-Null
$cihash = ConvertFrom-Json -InputObject $ci -AsHashtable

# Function to send formatted Slack message
function Send-FormattedSlackMessage {
    param(
        [string]$Uri,
        [hashtable]$WarningData,
        [hashtable]$AllVMData
    )
    
    $totalWarnings = 0
    $vcenterCount = 0
    
    foreach ($vc in $WarningData.Keys) {
        $totalWarnings += $WarningData[$vc].Count
        if ($WarningData[$vc].Count -gt 0) { $vcenterCount++ }
    }
    
    if ($totalWarnings -eq 0) {
        $message = ":white_check_mark: *VM DRS & CPU Monitoring - All Clear*`n"
        $message += "No warnings detected across all vCenters`n`n"
        $message += "*Summary of All VMs:*`n"
        
        foreach ($vc in $AllVMData.Keys | Sort-Object) {
            $message += "`n*$vc*:"
            foreach ($vm in $AllVMData[$vc] | Sort-Object Name) {
                $message += "`n  • $($vm.Name) - DRS: $($vm.DrsScore)% | CPU Ready: $($vm.CpuReady)% | CPU Usage: $($vm.CpuUsage)%"
            }
        }
    } else {
        $message = ":warning: *VM DRS & CPU Monitoring - Warnings Detected*`n"
        $message += "Total Warnings: *$totalWarnings* | vCenters with Issues: *$vcenterCount*`n`n"
        $message += "*Warnings by vCenter:*`n"
        
        foreach ($vc in $WarningData.Keys | Sort-Object) {
            if ($WarningData[$vc].Count -gt 0) {
                $message += "`n*$vc*:"
                foreach ($vm in $WarningData[$vc]) {
                    $warningReasons = @()
                    if ($vm.CpuReady -gt 4) { $warningReasons += "CPU Ready: $($vm.CpuReady)%" }
                    if ($vm.DrsScore -lt 70) { $warningReasons += "DRS Score: $($vm.DrsScore)%" }
                    
                    $message += "`n  • $($vm.Name) - $($warningReasons -join ', ') | CPU Usage: $($vm.CpuUsage)%"
                }
            }
        }
        
        $message += "`n`n*All VMs Summary:*`n"
        foreach ($vc in $AllVMData.Keys | Sort-Object) {
            $message += "`n*$vc*:"
            foreach ($vm in $AllVMData[$vc] | Sort-Object Name) {
                $status = if ($vm.CpuReady -gt 4 -or $vm.DrsScore -lt 70) { ":warning:" } else { ":white_check_mark:" }
                $message += "`n  $status $($vm.Name) - DRS: $($vm.DrsScore)% | CPU Ready: $($vm.CpuReady)% | CPU Usage: $($vm.CpuUsage)%"
            }
        }
    }
    
    # Add timestamp for tracking
    $message += "`n`n*Last Check:* $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss UTC')"
    
    Send-SlackMessage -Uri $Uri -Text $message
}

# Function to create a hash of the current VM status for change detection
function Get-VMStatusHash {
    param(
        [hashtable]$VMData
    )
    
    $statusString = ""
    foreach ($vc in $VMData.Keys | Sort-Object) {
        foreach ($vm in $VMData[$vc] | Sort-Object Name) {
            $statusString += "$($vm.Name):$($vm.DrsScore):$($vm.CpuReady):$($vm.CpuUsage)|"
        }
    }
    
    # Create a simple hash of the status string
    $hash = 0
    for ($i = 0; $i -lt $statusString.Length; $i++) {
        $hash = (($hash -shl 5) - $hash + [int]$statusString[$i]) -band 0xFFFFFFFF
    }
    return $hash
}

# Function to get VM DRS score
function Get-VMDRSScore {
    param(
        [Parameter(ValueFromPipeline=$true)]
        $VM
    )
    
    try {
        $vmView = Get-View $VM.Id
        $drsScore = $vmView.Runtime.DrsScore
        if ($drsScore -eq $null) {
            return 100  # Default to 100% if no DRS score available
        }
        return [math]::Round($drsScore, 1)
    }
    catch {
        Write-Host "Warning: Could not get DRS score for $($VM.Name): $($_.Exception.Message)"
        return 100
    }
}

# Function to get VM CPU readiness
function Get-VMCPUReady {
    param(
        [Parameter(ValueFromPipeline=$true)]
        $VM
    )
    
    try {
        $cpuReady = $VM | Get-Stat -Stat cpu.ready.summation -Realtime -MaxSamples 1 -ErrorAction SilentlyContinue
        if ($cpuReady) {
            # Convert from nanoseconds to percentage (assuming 100% = 1000ms = 1,000,000,000 nanoseconds)
            $cpuReadyPercent = ($cpuReady.Value / 10000000) * 100
            return [math]::Round($cpuReadyPercent, 2)
        }
        return 0
    }
    catch {
        Write-Host "Warning: Could not get CPU ready for $($VM.Name): $($_.Exception.Message)"
        return 0
    }
}

# Function to get VM CPU usage
function Get-VMCPUUsage {
    param(
        [Parameter(ValueFromPipeline=$true)]
        $VM
    )
    
    try {
        $cpuUsage = $VM | Get-Stat -Stat cpu.usage.average -Realtime -MaxSamples 1 -ErrorAction SilentlyContinue
        if ($cpuUsage) {
            return [math]::Round($cpuUsage.Value, 1)
        }
        return 0
    }
    catch {
        Write-Host "Warning: Could not get CPU usage for $($VM.Name): $($_.Exception.Message)"
        return 0
    }
}

$allVMData = @{}      # Store all VM data per vCenter
$warningData = @{}    # Store VMs with warnings per vCenter

foreach ($key in $cihash.Keys) {
    try {
        $cihash[$key].vcenter
        $cihash[$key].datacenter
        $cihash[$key].cluster
        $cihash[$key].datastore

        Connect-VIServer -Server $cihash[$key].vcenter -Credential (Import-Clixml $cihash[$key].secret) | Out-Null

        # Get all VMs that match CI naming pattern
        $virtualMachines = @(Get-VM | Where-Object { $_.Name -match '^ci-*' })
        
        Write-Host "Found $($virtualMachines.Count) CI VMs in $($cihash[$key].vcenter)"
        
        $vmData = @()
        $vmWarnings = @()

        foreach ($vm in $virtualMachines) {
            Write-Host "Processing VM: $($vm.Name) (Type: $($vm.GetType().Name))"
            
            try {
                # Get DRS score
                $drsScore = Get-VMDRSScore -VM $vm
                
                # Get CPU readiness
                $cpuReady = Get-VMCPUReady -VM $vm
                
                # Get CPU usage
                $cpuUsage = Get-VMCPUUsage -VM $vm
                
                # Create VM data object
                $vmInfo = [PSCustomObject]@{
                    Name = $vm.Name
                    DrsScore = $drsScore
                    CpuReady = $cpuReady
                    CpuUsage = $cpuUsage
                }
                
                $vmData += $vmInfo
                
                # Check for warnings
                if ($cpuReady -gt 4 -or $drsScore -lt 70) {
                    $vmWarnings += $vmInfo
                }
                
                Write-Host "$($vm.Name) - DRS: $drsScore%, CPU Ready: $cpuReady%, CPU Usage: $cpuUsage%"
            }
            catch {
                Write-Host "Error processing VM $($vm.Name): $($_.Exception.Message)"
                # Continue with next VM instead of failing completely
                continue
            }
        }
        
        # Store data for this vCenter
        $allVMData[$cihash[$key].vcenter] = $vmData
        if ($vmWarnings.Count -gt 0) {
            $warningData[$cihash[$key].vcenter] = $vmWarnings
        }

    }
    catch {
        $caught = Get-Error
        $errStr = $caught.ToString()

        $caught

        Send-SlackMessage -Uri $Env:SLACK_WEBHOOK_URI -Text ":x: *Error in VM DRS Monitoring script for $($cihash[$key].vcenter):*`n$errStr"
    }
    finally {
        Disconnect-VIServer -Server * -Force:$true -Confirm:$false
    }
}

# Get current status hash
$currentStatusHash = Get-VMStatusHash -VMData $allVMData

# Get previous status hash from environment variable (if available)
$previousStatusHash = 0
if ($Env:PREVIOUS_VM_DRS_STATUS_HASH) {
    try {
        $previousStatusHash = [int]$Env:PREVIOUS_VM_DRS_STATUS_HASH
    }
    catch {
        $previousStatusHash = 0
    }
}

# Only send Slack message if status changed or if this is the first run
if ($currentStatusHash -ne $previousStatusHash) {
    Send-FormattedSlackMessage -Uri $Env:SLACK_WEBHOOK_URI -WarningData $warningData -AllVMData $allVMData
    
    # Update environment variable for next run (these won't persist between cronjob runs, but that's okay)
    $Env:PREVIOUS_VM_DRS_STATUS_HASH = $currentStatusHash.ToString()
    
    Write-Host "Slack notification sent. Status changed. New hash: $currentStatusHash"
} else {
    Write-Host "No notification sent. Status unchanged. Current hash: $currentStatusHash"
}

exit 0

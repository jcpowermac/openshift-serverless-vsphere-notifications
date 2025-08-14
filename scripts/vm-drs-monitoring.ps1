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
        # Don't send "all clear" messages - this prevents spam
        Write-Host "No warnings detected. Skipping Slack notification to prevent spam."
        return
    }
    
    # Only send message when there are actual warnings
    $message = ":warning: *VM DRS & CPU Monitoring - Warnings Detected*`n"
    $message += "Total Warnings: *$totalWarnings* | vCenters with Issues: *$vcenterCount*`n`n"
    
    foreach ($vc in $WarningData.Keys | Sort-Object) {
        if ($WarningData[$vc].Count -gt 0) {
            $message += "*$vc*`n"
            foreach ($vm in $WarningData[$vc] | Sort-Object Name) {
                $warningReasons = @()
                if ($vm.CpuReady -gt 4) { $warningReasons += "CPU Ready: $($vm.CpuReady)%" }
                if ($vm.DrsScore -lt 70) { $warningReasons += "DRS Score: $($vm.DrsScore)%" }
                
                $message += "  • $($vm.Name)`n"
                $message += "    - Issues: $($warningReasons -join ', ')`n"
                $message += "    - CPU Usage: $($vm.CpuUsage)%`n"
            }
            $message += "`n"
        }
    }
    
    # Add timestamp for tracking
    $message += "*Last Check:* $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss UTC')"
    
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

Write-Host "Current status hash: $currentStatusHash"
Write-Host "Previous status hash: $previousStatusHash"
Write-Host "Total vCenters with data: $($allVMData.Count)"
Write-Host "Total VMs found: $(($allVMData.Values | ForEach-Object { $_.Count } | Measure-Object -Sum).Sum)"

# Only send Slack message if:
# 1. Status changed AND
# 2. We actually have VM data to report AND
# 3. We have actual warnings to report
if ($currentStatusHash -ne $previousStatusHash -and $allVMData.Count -gt 0) {
    # Check if we have actual VM data (not just empty arrays)
    $hasActualData = $false
    foreach ($vc in $allVMData.Keys) {
        if ($allVMData[$vc].Count -gt 0) {
            $hasActualData = $true
            break
        }
    }
    
    if ($hasActualData) {
        # Only send if we have warnings
        if ($warningData.Count -gt 0) {
            Write-Host "Status changed and warnings detected. Sending Slack notification..."
            Send-FormattedSlackMessage -Uri $Env:SLACK_WEBHOOK_URI -WarningData $warningData -AllVMData $allVMData
            
            # Update environment variable for next run (these won't persist between cronjob runs, but that's okay)
            $Env:PREVIOUS_VM_DRS_STATUS_HASH = $currentStatusHash.ToString()
            
            Write-Host "Slack notification sent. Status changed. New hash: $currentStatusHash"
        } else {
            Write-Host "Status changed but no warnings detected. Skipping Slack notification."
            $Env:PREVIOUS_VM_DRS_STATUS_HASH = $currentStatusHash.ToString()
        }
    } else {
        Write-Host "No VMs found to report. Skipping Slack notification."
        $Env:PREVIOUS_VM_DRS_STATUS_HASH = $currentStatusHash.ToString()
    }
} else {
    if ($allVMData.Count -eq 0) {
        Write-Host "No VMs found. Skipping Slack notification."
    } else {
        Write-Host "No notification sent. Status unchanged. Current hash: $currentStatusHash"
    }
}

exit 0

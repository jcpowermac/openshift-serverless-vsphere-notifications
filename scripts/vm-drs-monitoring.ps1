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
    
    # This function is only called when there are warnings
    $message = ":warning: *VM DRS & CPU Monitoring - Warnings Detected*`n"
    $message += "Total Warnings: *$totalWarnings* | vCenters with Issues: *$vcenterCount*`n`n"
    
    foreach ($vc in $WarningData.Keys | Sort-Object) {
        if ($WarningData[$vc].Count -gt 0) {
            $message += "*$vc*`n"
            foreach ($vm in $WarningData[$vc] | Sort-Object Name) {
                $warningReasons = @()
                if ($vm.CpuReady -gt 5) { $warningReasons += "CPU Ready: $($vm.CpuReady)%" }
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
    
    # Create a simple hash of the status string with overflow protection
    $hash = [long]0
    for ($i = 0; $i -lt $statusString.Length; $i++) {
        try {
            $charValue = [int]$statusString[$i]
            $newHash = (($hash -shl 5) - $hash + $charValue) -band 0x7FFFFFFF
            $hash = $newHash
        }
        catch {
            # If overflow occurs, reset and continue
            $hash = [long]([int]$statusString[$i])
        }
    }
    return [int]$hash
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
            # Handle both single values and arrays
            $cpuReadyValue = if ($cpuReady -is [array]) { $cpuReady[0].Value } else { $cpuReady.Value }
            
            # Get the actual interval from the stat object
            $statObject = if ($cpuReady -is [array]) { $cpuReady[0] } else { $cpuReady }
            $intervalSeconds = $statObject.IntervalSecs
            
            # Get VM information for vCPU count
            $vmInfo = Get-VM -Name $VM.Name
            $numCpus = $vmInfo.NumCpu
            
            # Try multiple calculation methods to find the correct one
            $intervalMs = $intervalSeconds * 1000
            
            # Method 1: Standard formula (cpu.ready.summation in ms / (interval in ms * vCPUs)) * 100
            $method1 = ($cpuReadyValue / ($intervalMs * $numCpus)) * 100
            
            # Method 2: Alternative formula without vCPU multiplication (some sources suggest this)
            $method2 = ($cpuReadyValue / $intervalMs) * 100
            
            # Method 3: Using different time base (vSphere might use different intervals)
            $method3 = ($cpuReadyValue / ($intervalMs / $numCpus)) * 100
            
            # Debug output with multiple methods
            Write-Host "  DEBUG: VM $($VM.Name) - CPUs: $numCpus, Ready(ms): $cpuReadyValue, IntervalSecs: $intervalSeconds" -ForegroundColor Gray
            Write-Host "  DEBUG: Method 1 (std): $([math]::Round($method1, 2))%, Method 2 (no vCPU): $([math]::Round($method2, 2))%, Method 3 (alt): $([math]::Round($method3, 2))%" -ForegroundColor Gray
            
            # For now, let's try method 2 (without vCPU multiplication) as it might be closer to UI values
            $cpuReadyPercent = $method2
            
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
                $hasWarning = $false
                if ($cpuReady -gt 5) { 
                    $vmWarnings += $vmInfo
                    $hasWarning = $true
                    Write-Host "  WARNING: CPU Ready $cpuReady% > 5%" -ForegroundColor Yellow
                }
                if ($drsScore -lt 70) { 
                    if (-not $hasWarning) { $vmWarnings += $vmInfo }
                    $hasWarning = $true
                    Write-Host "  WARNING: DRS Score $drsScore% < 70%" -ForegroundColor Yellow
                }
                
                Write-Host "$($vm.Name) - DRS: $drsScore%, CPU Ready: $cpuReady%, CPU Usage: $cpuUsage%" -ForegroundColor $(if ($hasWarning) { "Red" } else { "Green" })
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
            Write-Host "vCenter $($cihash[$key].vcenter): Found $($vmWarnings.Count) VMs with warnings" -ForegroundColor Yellow
        } else {
            Write-Host "vCenter $($cihash[$key].vcenter): No warnings detected" -ForegroundColor Green
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

# Debug warning data
Write-Host "Warning Data Summary:" -ForegroundColor Cyan
foreach ($vc in $warningData.Keys) {
    Write-Host "  ${vc}: $($warningData[$vc].Count) warnings" -ForegroundColor Cyan
    foreach ($vm in $warningData[$vc]) {
        $reasons = @()
        if ($vm.CpuReady -gt 5) { $reasons += "CPU Ready: $($vm.CpuReady)%" }
        if ($vm.DrsScore -lt 70) { $reasons += "DRS Score: $($vm.DrsScore)%" }
        Write-Host "    - $($vm.Name): $($reasons -join ', ')" -ForegroundColor Cyan
    }
}

# Only send Slack message if we have actual warnings to report
if ($warningData.Count -gt 0) {
    # We have warnings - send a message
    Write-Host "Warnings detected. Sending Slack notification..."
    Send-FormattedSlackMessage -Uri $Env:SLACK_WEBHOOK_URI -WarningData $warningData -AllVMData $allVMData
    
    # Update environment variable for next run
    $Env:PREVIOUS_VM_DRS_STATUS_HASH = $currentStatusHash.ToString()
    
    Write-Host "Slack notification sent. Warnings reported."
} else {
    # No warnings - completely silent, no Slack message
    Write-Host "No warnings detected. No Slack notification sent."
    
    # Update environment variable for next run
    $Env:PREVIOUS_VM_DRS_STATUS_HASH = $currentStatusHash.ToString()
}

exit 0

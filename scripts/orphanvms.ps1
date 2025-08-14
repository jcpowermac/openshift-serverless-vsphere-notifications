#!/bin/pwsh

. /var/run/config/vcenter/variables.ps1

Set-PowerCLIConfiguration -InvalidCertificateAction:Ignore -Confirm:$false | Out-Null

$cihash = ConvertFrom-Json -InputObject $ci -AsHashtable

# Function to send formatted Slack message
function Send-FormattedSlackMessage {
    param(
        [string]$Uri,
        [hashtable]$OrphanData
    )
    
    $totalOrphans = 0
    $vcenterCount = 0
    
    foreach ($vc in $OrphanData.Keys) {
        $totalOrphans += $OrphanData[$vc].Count
        if ($OrphanData[$vc].Count -gt 0) { $vcenterCount++ }
    }
    
    if ($totalOrphans -eq 0) {
        $message = ":white_check_mark: *Orphan VM Status - All Clear*`n"
        $message += "No orphaned VMs detected across all vCenters"
    } else {
        $message = ":ghost: *Orphan VM Status - Cleanup Required*`n"
        $message += "Total Orphaned VMs: *$totalOrphans* | vCenters with Orphans: *$vcenterCount*`n`n"
        $message += "*Orphaned VMs by vCenter:*`n"
        
        foreach ($vc in $OrphanData.Keys | Sort-Object) {
            if ($OrphanData[$vc].Count -gt 0) {
                $message += "`n*$vc*:"
                foreach ($vm in $OrphanData[$vc]) {
                    $message += "`n  • $vm"
                }
            }
        }
    }
    
    # Add timestamp for tracking
    $message += "`n`n*Last Check:* $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss UTC')"
    
    Send-SlackMessage -Uri $Uri -Text $message
}

# Function to create a hash of the current orphan VM status for change detection
function Get-OrphanStatusHash {
    param(
        [hashtable]$OrphanData
    )
    
    $statusString = ""
    foreach ($vc in $OrphanData.Keys | Sort-Object) {
        $vms = $OrphanData[$vc] | Sort-Object
        $statusString += "$($vc):$($vms -join ',')|"
    }
    
    # Create a simple hash of the status string
    $hash = 0
    for ($i = 0; $i -lt $statusString.Length; $i++) {
        $hash = (($hash -shl 5) - $hash + [int]$statusString[$i]) -band 0xFFFFFFFF
    }
    return $hash
}

$allOrphanData = @{}  # Store orphaned VMs per vCenter

foreach ($key in $cihash.Keys) {
    $cihash[$key].vcenter
    try {

        Connect-VIServer -Server $cihash[$key].vcenter -Credential (Import-Clixml $cihash[$key].secret) | Out-Null

        $virtualMachines = @(Get-VM | Where-Object { $_.Name -match '^ci-*' })

        foreach ($vm in $virtualMachines) {
            if ($vm.PowerState -eq 'PoweredOff') { 
                $disks = Get-harddisk -VM $vm

                foreach ($d in $disks) {
                    if ($d.CapacityGB -eq 0) {
                        $d | Remove-HardDisk -DeletePermanently:$false -Confirm:$false

                        Remove-VM -VM $vm -DeletePermanently:$true -Confirm:$false
                        
                        # Store orphaned VM for this vCenter
                        if (!$allOrphanData.ContainsKey($cihash[$key].vcenter)) {
                            $allOrphanData[$cihash[$key].vcenter] = @()
                        }
                        $allOrphanData[$cihash[$key].vcenter] += $vm.Name
                        break
                    }
                }
            }
        }

    }
    catch {
        $caught = Get-Error
        $errStr = $caught.ToString()

        $caught

        Send-SlackMessage -Uri $Env:SLACK_WEBHOOK_URI -Text ":x: *Error in Orphan VMs script for $($cihash[$key].vcenter)*`n$errStr"
        exit 1
    }
    finally {
        Disconnect-VIServer -Server * -Force:$true -Confirm:$false
    }
}

# Get current status hash
$currentStatusHash = Get-OrphanStatusHash -OrphanData $allOrphanData

# Get previous status hash from environment variable (if available)
$previousStatusHash = 0
if ($Env:PREVIOUS_ORPHAN_STATUS_HASH) {
    try {
        $previousStatusHash = [int]$Env:PREVIOUS_ORPHAN_STATUS_HASH
    }
    catch {
        $previousStatusHash = 0
    }
}

# Only send Slack message if status changed or if this is the first run
if ($currentStatusHash -ne $previousStatusHash) {
    Send-FormattedSlackMessage -Uri $Env:SLACK_WEBHOOK_URI -OrphanData $allOrphanData
    
    # Update environment variable for next run (these won't persist between cronjob runs, but that's okay)
    $Env:PREVIOUS_ORPHAN_STATUS_HASH = $currentStatusHash.ToString()
    
    Write-Host "Slack notification sent. Status changed. New hash: $currentStatusHash"
} else {
    Write-Host "No notification sent. Status unchanged. Current hash: $currentStatusHash"
}

exit 0

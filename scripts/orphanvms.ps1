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
    
    Send-SlackMessage -Uri $Uri -Text $message
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

        Send-SlackMessage -Uri $Env:SLACK_WEBHOOK_URI -Text ":x: *Error in Orphan VMs script for $($cihash[$key].vcenter):*`n$errStr"
        exit 1
    }
    finally {
        Disconnect-VIServer -Server * -Force:$true -Confirm:$false
    }
}

# Send consolidated message for all vCenters
if ($allOrphanData.Count -gt 0) {
    Send-FormattedSlackMessage -Uri $Env:SLACK_WEBHOOK_URI -OrphanData $allOrphanData
} else {
    # Send "all clear" message if no orphaned VMs found
    Send-FormattedSlackMessage -Uri $Env:SLACK_WEBHOOK_URI -OrphanData @{}
}

exit 0

#!/bin/pwsh

. /var/run/config/vcenter/variables.ps1

Set-PowerCLIConfiguration -InvalidCertificateAction:Ignore -Confirm:$false | Out-Null

$cihash = ConvertFrom-Json -InputObject $ci -AsHashtable

# Function to send formatted Slack message
function Send-FormattedSlackMessage {
    param(
        [string]$Uri,
        [hashtable]$ResourcePoolData
    )
    
    $totalResourcePools = ($ResourcePoolData.Values | Measure-Object -Sum).Sum
    $vcenterCount = $ResourcePoolData.Count
    
    $message = ":pools: *Resource Pool Cleanup Summary*`n"
    $message += "Total Resource Pools: *$totalResourcePools* | vCenters: *$vcenterCount*`n`n"
    $message += "*Resource Pool Count by vCenter:*`n"
    
    foreach ($vc in $ResourcePoolData.Keys | Sort-Object) {
        $count = $ResourcePoolData[$vc]
        $message += "`n• $vc`: $count resource pools"
    }
    
    Send-SlackMessage -Uri $Uri -Text $message
}

$resourcePoolData = @{}  # Store resource pool counts per vCenter

foreach ($key in $cihash.Keys) {
    $cihash[$key].vcenter
    try {

        Connect-VIServer -Server $cihash[$key].vcenter -Credential (Import-Clixml $cihash[$key].secret) | Out-Null

        $resourcePools = @(Get-ResourcePool | Where-Object { $_.Name -match '^ci*|^qeci*' })
        
        # Store resource pool count for this vCenter
        $resourcePoolData[$cihash[$key].vcenter] = $resourcePools.Count

        foreach ($rp in $resourcePools) {
            [array]$resourcePoolVirtualMachines = $rp | Get-VM
            if ($resourcePoolVirtualMachines.Length -eq 0) {
                Write-Host "Remove RP: $($rp.Name)"
                Remove-ResourcePool -ResourcePool $rp -Confirm:$false -ErrorAction Continue
            }
        }
    }
    catch {
        $caught = Get-Error
        $errStr = $caught.ToString()

        $caught

        Send-SlackMessage -Uri $Env:SLACK_WEBHOOK_URI -Text ":x: *Error in Resource Pools script for $($cihash[$key].vcenter):*`n$errStr"
        exit 1
    }
    finally {
        Disconnect-VIServer -Server * -Force:$true -Confirm:$false
    }
}

# Send consolidated message for all vCenters
if ($resourcePoolData.Count -gt 0) {
    Send-FormattedSlackMessage -Uri $Env:SLACK_WEBHOOK_URI -ResourcePoolData $resourcePoolData
}

exit 0

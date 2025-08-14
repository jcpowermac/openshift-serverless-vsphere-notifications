#!/bin/pwsh
. /var/run/config/vcenter/variables.ps1

Set-PowerCLIConfiguration -InvalidCertificateAction:Ignore -Confirm:$false | Out-Null
$cihash = ConvertFrom-Json -InputObject $ci -AsHashtable

# Function to send formatted Slack message
function Send-FormattedSlackMessage {
    param(
        [string]$Uri,
        [hashtable]$LockoutData
    )
    
    $totalLockedAccounts = 0
    $vcenterCount = 0
    
    foreach ($vc in $LockoutData.Keys) {
        $totalLockedAccounts += $LockoutData[$vc].Count
        if ($LockoutData[$vc].Count -gt 0) { $vcenterCount++ }
    }
    
    if ($totalLockedAccounts -eq 0) {
        $message = ":white_check_mark: *Account Lockout Status - All Clear*`n"
        $message += "No locked accounts detected across all vCenters"
    } else {
        $message = ":warning: *Account Lockout Status - Action Required*`n"
        $message += "Total Locked Accounts: *$totalLockedAccounts* | vCenters with Lockouts: *$vcenterCount*`n`n"
        $message += "*Locked Accounts by vCenter:*`n"
        
        foreach ($vc in $LockoutData.Keys | Sort-Object) {
            if ($LockoutData[$vc].Count -gt 0) {
                $message += "`n*$vc*:"
                foreach ($account in $LockoutData[$vc]) {
                    $message += "`n  • $account"
                }
            }
        }
    }
    
    # Add timestamp for tracking
    $message += "`n`n*Last Check:* $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss UTC')"
    
    Send-SlackMessage -Uri $Uri -Text $message
}

# Function to create a hash of the current lockout status for change detection
function Get-LockoutStatusHash {
    param(
        [hashtable]$LockoutData
    )
    
    $statusString = ""
    foreach ($vc in $LockoutData.Keys | Sort-Object) {
        $accounts = $LockoutData[$vc] | Sort-Object
        $statusString += "$($vc):$($accounts -join ',')|"
    }
    
    # Create a simple hash of the status string
    $hash = 0
    for ($i = 0; $i -lt $statusString.Length; $i++) {
        $hash = (($hash -shl 5) - $hash + [int]$statusString[$i]) -band 0xFFFFFFFF
    }
    return $hash
}

$allLockoutData = @{}  # Store locked accounts per vCenter

foreach ($key in $cihash.Keys) {
    # skip devqe its goofy and we don't care
    if ( $key -eq "devqe" ) {
        continue
    }

    try {
        $cihash[$key].vcenter

        Connect-SsoAdminServer  -SkipCertificateCheck -Server $cihash[$key].vcenter -Credential (Import-Clixml $cihash[$key].secret) 

        $user, $domain = $DefaultSsoAdminServers.User -split '@'

        $ssoUsers = Get-SsoPersonUser -Name "ci*" -Domain $domain

        $lockedSsoAccounts = @()

        foreach ($user in $ssoUsers) {
            if ($user.Locked) {
                $lockedSsoAccounts += $user.Name
            }
        }

        # Store locked accounts for this vCenter
        if ($lockedSsoAccounts.Count -gt 0) {
            $allLockoutData[$cihash[$key].vcenter] = $lockedSsoAccounts
        }

    }
    catch {
        $caught = Get-Error
        $errStr = $caught.ToString()
        $caught
        # Always send error messages regardless of frequency
        Send-SlackMessage -Uri $Env:SLACK_WEBHOOK_URI -Text ":x: *Error in Account Lockout script for $($cihash[$key].vcenter)*`n$errStr"
    }
    finally {
        Disconnect-SsoAdminServer -Server * 
    }
}

# Get current status hash
$currentStatusHash = Get-LockoutStatusHash -LockoutData $allLockoutData

# Get previous status hash from environment variable (if available)
$previousStatusHash = 0
if ($Env:PREVIOUS_LOCKOUT_STATUS_HASH) {
    try {
        $previousStatusHash = [int]$Env:PREVIOUS_LOCKOUT_STATUS_HASH
    }
    catch {
        $previousStatusHash = 0
    }
}

# Only send Slack message if status changed or if this is the first run
if ($currentStatusHash -ne $previousStatusHash) {
    Send-FormattedSlackMessage -Uri $Env:SLACK_WEBHOOK_URI -LockoutData $allLockoutData
    
    # Update environment variable for next run (these won't persist between cronjob runs, but that's okay)
    $Env:PREVIOUS_LOCKOUT_STATUS_HASH = $currentStatusHash.ToString()
    
    Write-Host "Slack notification sent. Status changed. New hash: $currentStatusHash"
} else {
    Write-Host "No notification sent. Status unchanged. Current hash: $currentStatusHash"
}

exit 0

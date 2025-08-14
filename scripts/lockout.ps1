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
    
    Send-SlackMessage -Uri $Uri -Text $message
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
        Send-SlackMessage -Uri $Env:SLACK_WEBHOOK_URI -Text ":x: *Error in Account Lockout script for $($cihash[$key].vcenter):*`n$errStr"
    }
    finally {
        Disconnect-SsoAdminServer -Server * 
    }
}

# Send consolidated message for all vCenters
if ($allLockoutData.Count -gt 0) {
    Send-FormattedSlackMessage -Uri $Env:SLACK_WEBHOOK_URI -LockoutData $allLockoutData
} else {
    # Send "all clear" message if no locked accounts found
    Send-FormattedSlackMessage -Uri $Env:SLACK_WEBHOOK_URI -LockoutData @{}
}

exit 0

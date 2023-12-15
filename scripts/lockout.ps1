#!/bin/pwsh
. /var/run/config/vcenter/variables.ps1

Set-PowerCLIConfiguration -InvalidCertificateAction:Ignore -Confirm:$false | Out-Null
$cihash = ConvertFrom-Json -InputObject $ci -AsHashtable
$slackMessage = @"
*** WARNING ci account locked out ***
vcenter: {0}
account(s): {1}
"@

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
                $lockedSsoAccounts.Add($user.Name)
            }
        }

        if ($lockedSsoAccounts.Count -gt 0) {
            Send-SlackMessage -Uri $Env:SLACK_WEBHOOK_URI -Text ($slackMessage -f $cihash[$key].vcenter, $lockedSsoAccounts -join " ")
        }

    }
    catch {
        $caught = Get-Error
        $errStr = $caught.ToString()
        $caught
        Send-SlackMessage -Uri $Env:SLACK_WEBHOOK_URI -Text $errStr
    }
    finally {
        Disconnect-SsoAdminServer -Server * 
    }
}


exit 0

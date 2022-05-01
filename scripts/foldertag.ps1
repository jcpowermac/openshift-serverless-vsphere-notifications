#!/bin/pwsh
. /var/run/config/vcenter/variables.ps1

Set-PowerCLIConfiguration -InvalidCertificateAction:Ignore -Confirm:$false | Out-Null
$cihash = ConvertFrom-Json -InputObject $ci -AsHashtable
$slackMessage = @"
Removing Folders and Tags
vcenter: {0}
"@

$deleteday = (Get-Date).AddDays(-4)

foreach ($key in $cihash.Keys) {
    $cihash[$key].vcenter
    $cihash[$key].datacenter
    $cihash[$key].cluster
    $cihash[$key].datastore

    try {
        Connect-VIServer -Server $cihash[$key].vcenter -Credential (Import-Clixml $cihash[$key].secret) | Out-Null
        Send-SlackMessage -Uri $Env:SLACK_WEBHOOK_URI -Text ($slackMessage -f $cihash[$key].vcenter)

        $folders = Get-Folder | Where-Object { $_.IsChildTypeVm -eq $true }
        foreach ($f in $folders) {
            $length = (($f | Get-View).ChildEntity.Length)

            if ($f.Name -eq "debug") {
                continue
            }

            if ($length -eq 0) {
                try {
                    $f | Remove-Folder -DeletePermanently -Confirm:$false

                    $tag = Get-Tag -Name $f.Name
                    $tc = Get-TagCategory -Name $tag.Category

                    Write-Host "Removing Tag: $($tag.Name), Removing TagCategory: $($tc.Name), Remove Folder: $($f.Name)"

                    $tag | Remove-Tag -Confirm:$False -ErrorAction Continue
                    $tc | Remove-TagCategory -Confirm:$False -ErrorAction Continue
                }
                catch {}
            }
        }
    }
    catch {
        Get-Error
        exit 1
    }
    finally {
        Disconnect-VIServer -Server * -Force:$true -Confirm:$false
    }
}

exit 0

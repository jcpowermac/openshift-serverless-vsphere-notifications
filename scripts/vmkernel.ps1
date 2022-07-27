#!/bin/pwsh
. /var/run/config/vcenter/variables.ps1

Set-PowerCLIConfiguration -InvalidCertificateAction:Ignore -Confirm:$false | Out-Null
$cihash = ConvertFrom-Json -InputObject $ci -AsHashtable

$slackMessage = @"
vmkernel
vcenter: {0}
SideIndicator: {1}
Messages: {2}
"@

$newFile = "/projects/new.log"
$oldFile = "/projects/old.log"

#$messages = @('lost connection','nfs','failure')
$messages = @('lost connection')

if (-not(Test-Path -Path $oldFile -PathType Leaf)) {
    $null = New-Item -ItemType File -Path $oldFile -Force
}


while ($true) {
    foreach ($key in $cihash.Keys) {
        try {
            $cihash[$key].vcenter
            $cihash[$key].datacenter
            $cihash[$key].cluster
            $cihash[$key].datastore

            Connect-VIServer -Server $cihash[$key].vcenter -Credential (Import-Clixml $cihash[$key].secret) | Out-Null

            $hosts = Get-VMHost

            $hosts | ForEach-Object {
                $entries = ($_ | Get-Log -Key "vmkernel" -StartLineNum 1 -NumLines 10000 ).Entries

                $messages | ForEach-Object {
                    $entries -imatch $_ | Out-File -Append -FilePath $newFile
                }

            }
            $compare = Compare-Object -ReferenceObject (Get-Content $oldFile) -DifferenceObject (Get-Content $newFile)
            if ($null -ne $compare) {
                Send-SlackMessage -Uri $Env:SLACK_WEBHOOK_URI -Text ($slackMessage -f $cihash[$key].vcenter, $compare.SideIndicator, $compare.InputObject)
            }
        }
        catch {
            Get-Error
        }
        finally {
            Get-Content -Path $newFile -Raw | Set-Content -Path $oldFile
            #Move-Item -Force:$true -Confirm:$false -Path "/var/run/secret/logs/new.log" -Destination "/var/run/secret/logs/old.log"
            Disconnect-VIServer -Server * -Force:$true -Confirm:$false
        }
    }


    Write-Host "Starting to sleep..."

    Start-Sleep -Seconds 3600 
}

#!/bin/pwsh
. /var/run/config/vcenter/variables.ps1

Set-PowerCLIConfiguration -InvalidCertificateAction:Ignore -Confirm:$false | Out-Null
$cihash = ConvertFrom-Json -InputObject $ci -AsHashtable
$slackMessage = @"
vcenter: {0}
"@

$slackMessage = @"
vmkernel
vcenter: {0}
SideIndicator: {1}
Messages: {2}
"@

#$messages = @('lost connection','nfs','failure')
$messages = @('lost connection')

#if (-not(Test-Path -Path "/var/run/secret/logs/old.log" -PathType Leaf)) {
#    $null = New-Item -ItemType File -Path "/var/run/secret/logs/old.log" -Force 
#}

ls -alh /var/run/secret/logs/

foreach ($key in $cihash.Keys) {
    try {
        $cihash[$key].vcenter
        $cihash[$key].datacenter
        $cihash[$key].cluster
        $cihash[$key].datastore

        Connect-VIServer -Server $cihash[$key].vcenter -Credential (Import-Clixml $cihash[$key].secret) | Out-Null

        $hosts = Get-VMHost

        $hosts | ForEach-Object {

            $_.Name

            $entries = ($_ | Get-Log -Key "vmkernel" -StartLineNum 1 -NumLines 10000 ).Entries

            $messages | ForEach-Object {
                $entries -imatch $_ | Out-File -Append -FilePath "/var/run/secret/logs/new.log"
            }
            $compare = Compare-Object -ReferenceObject (Get-Content "/var/run/secret/logs/old.log") -DifferenceObject (Get-Content "/var/run/secret/logs/new.log")

            if ($compare -ne $null) {
                Send-SlackMessage -Uri $Env:SLACK_WEBHOOK_URI -Text ($slackMessage -f $cihash[$key].vcenter, $compare.SideIndicator, $compare.InputObject)
            }
        }
    }
    catch {
        Get-Error
    }
    finally {
        Get-Content -Path "/var/run/secret/logs/new.log" -Raw | Set-Content -Path "/var/run/secret/logs/old.log"
        #Move-Item -Force:$true -Confirm:$false -Path "/var/run/secret/logs/new.log" -Destination "/var/run/secret/logs/old.log"
        Disconnect-VIServer -Server * -Force:$true -Confirm:$false
    }
}

exit 0

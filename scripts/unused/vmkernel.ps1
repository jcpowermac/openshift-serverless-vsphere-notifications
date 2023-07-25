#!/bin/pwsh
. /var/run/config/vcenter/variables.ps1

Set-PowerCLIConfiguration -InvalidCertificateAction:Ignore -Confirm:$false | Out-Null
$cihash = ConvertFrom-Json -InputObject $ci -AsHashtable

$slackMessage = @"
vmkernel
vcenter: {0}
host: {1}
SideIndicator: {2}
Messages: {3}
"@

while ($true) {
    $key = "ibm"
    $cihash[$key].vcenter
    $cihash[$key].datacenter
    $cihash[$key].cluster
    $cihash[$key].datastore

    Connect-VIServer -Server $cihash[$key].vcenter -Credential (Import-Clixml $cihash[$key].secret) | Out-Null

    $hosts = Get-VMHost

    $hosts | ForEach-Object {
        $oldFile = "$($_.Id).old"
        $newFile = "$($_.Id).new"

        if (-not(Test-Path -Path $oldFile -PathType Leaf)) {
            $null = New-Item -ItemType File -Path $oldFile -Force
        }
        $entries = ($_ | Get-Log -Key "vmkernel" -StartLineNum 1 -NumLines 10000 ).Entries

        $lostConnection = $entries -imatch 'lost connection'

        if ($lostConnection) {
            $lostConnection | Out-File -FilePath $newFile

            $oldContent = Get-Content $oldFile
            if ($null -eq $oldContent ) {
                $oldContent = ""
            }

            $compare = Compare-Object -ReferenceObject $oldContent -DifferenceObject (Get-Content $newFile)

            Move-Item -Force:$true -Confirm:$false -Path $newFile -Destination $oldFile
            if (Test-Path -Path $newFile -PathType Leaf) {
                Remove-Item -Force:$true -Confirm:$false -Path $newFile
            }
            if ($null -ne $compare) {
                $sideIndicator = ""
                $inputObject = ""
                $compare | ForEach-Object {
                    $sideIndicator += $_.SideIndicator
                    $inputObject += $_.InputObject
                }

                Send-SlackMessage -Uri $Env:SLACK_WEBHOOK_URI -Text ($slackMessage -f $cihash[$key].vcenter, $_, $sideIndicator, $inputObject)
            }
        }
    }

    Disconnect-VIServer -Server * -Force:$true -Confirm:$false
    Write-Host "Starting to sleep..."

    Start-Sleep -Seconds 3600
}

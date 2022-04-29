#!/bin/pwsh

. /var/run/config/vcenter/variables.ps1

$cihash = ConvertFrom-Json -InputObject $ci -AsHashtable

foreach ($key in $cihash.Keys) {

    $Env:GOVC_URL = $cihash[$key].vcenter
    $Env:GOVC_INSECURE = 1

    try {
        Send-SlackMessage -Uri $Env:SLACK_WEBHOOK_URI -Text "Cleaning: $($cihash[$key].vcenter)"

        Set-PowerCLIConfiguration -InvalidCertificateAction:Ignore -Confirm:$false | Out-Null
        Connect-VIServer -Server $cihash[$key].vcenter -Credential (Import-Clixml $cihash[$key].secret) | Out-Null


        $storagePolicies = (Get-SpbmStoragePolicy | Where-Object -Property Name -Like "*ci*" | Where-Object -Property CreationTime -LT $deleteday )

        foreach ($policy in $storagePolicies) {
            Remove-SpbmStoragePolicy -StoragePolicy $policy -Confirm:$false
        }

        $govcOutput = "./volumes.json"
        $govcError = "./govcerror.txt"
        $process = Start-Process -Wait -RedirectStandardError $govcError -RedirectStandardOutput $govcOutput -FilePath /bin/govc -ArgumentList @("volume.ls", "-json", "-ds $($cihash[$key].datastore)") -PassThru

        if ($process.ExitCode -eq 0) {
            $volumeHash = (Get-Content -Path $govcOutput | ConvertFrom-Json -AsHashtable)
            foreach ($vol in $volumeHash["Volume"]) {
                $volumeId = $vol["VolumeId"]["Id"]
                $clusterId = $vol["Metadata"]["ContainerCluster"]["ClusterId"]
                $clusterInventory = Get-Inventory -Name $clusterId -ErrorAction Continue

                if ($clusterInventory.Count -eq 0) {
                    Start-Process -Wait -FilePath /bin/govc -ArgumentList @("volume.rm", $volumeId)
                }
                else {
                    Write-Output $clusterInventory
                }
            }
        }
        else {
            Get-Content -Path $govcError
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

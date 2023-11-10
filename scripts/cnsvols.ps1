#!/bin/pwsh

. /var/run/config/vcenter/variables.ps1

Set-PowerCLIConfiguration -InvalidCertificateAction:Ignore -Confirm:$false | Out-Null
$cihash = ConvertFrom-Json -InputObject $ci -AsHashtable

$slackMessage = @"
cns volumes
vcenter: {0}
count: {1}
"@


foreach ($key in $cihash.Keys) {
    $credential = Import-Clixml -Path $cihash[$key].secret

    $Env:GOVC_PASSWORD = $credential.GetNetworkCredential().Password
    $Env:GOVC_USERNAME = $credential.GetNetworkCredential().UserName
    $Env:GOVC_URL = $cihash[$key].vcenter
    $Env:GOVC_DATACENTER = $cihash[$key].datacenter
    $Env:GOVC_INSECURE = 1
    try {
        Connect-VIServer -Server $cihash[$key].vcenter -Credential $credential | Out-Null

        $govcOutput = "./volumes.json"
        $govcError = "./govcerror.txt"

        $process = Start-Process -Wait -RedirectStandardError $govcError -RedirectStandardOutput $govcOutput -FilePath /bin/govc -ArgumentList @("volume.ls", "-json", "-ds $($cihash[$key].datastore)") -PassThru -ErrorAction Continue

        if ($process.ExitCode -eq 0) {
            $volumeHash = (Get-Content -Path $govcOutput | ConvertFrom-Json -AsHashtable)

            Send-SlackMessage -Uri $Env:SLACK_WEBHOOK_URI -Text ($slackMessage -f $cihash[$key].vcenter, $volumeHash.Volume.Count)

            foreach ($vol in $volumeHash["Volume"]) {
                $volumeId = $vol["VolumeId"]["Id"]
                $clusterId = $vol["Metadata"]["ContainerCluster"]["ClusterId"]
                $clusterInventory = Get-Inventory -Name $clusterId -ErrorAction Continue

                if ($clusterInventory.Count -eq 0) {
                    Write-Host "Delete: $($volumeId)"

                    Start-Process -Wait -FilePath /bin/govc -ArgumentList @("volume.rm", $volumeId)
                }
            }
        }
        else {
            Send-SlackMessage -Uri $Env:SLACK_WEBHOOK_URI -Text "CNS Volume clean up didn't run $($cihash[$key].vcenter)" 
            Get-Content -Path $govcError
        }
    }
    catch {
        $caught = Get-Error
        $errStr = $caught.ToString()
        $caught
        Send-SlackMessage -Uri $Env:SLACK_WEBHOOK_URI -Text $errStr
    }
    finally {
        Disconnect-VIServer -Server * -Force:$true -Confirm:$false
    }

    # the command below will reconcile datastore inventory which can get out of sync
    # the vSphere inventory of managed virtual disks can become temporarily out of synch with datastore disk backing metadata.
    # This problem can be due to a transient condition, such as an I/O error, or it can happen if a datastore is briefly inaccessible.
    # This problem has been observed only under stress testing.
    Start-Process -Wait -FilePath /bin/govc -ArgumentList @("disk.ls", "-R", "-ds", $cihash[$key].datastore) -ErrorAction Continue
}
exit 0

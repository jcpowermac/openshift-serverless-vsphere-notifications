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

    $Env:GOVC_URL = $cihash[$key].vcenter
    $Env:GOVC_DATACENTER = $cihash[$key].datacenter
    $Env:GOVC_INSECURE = 1

    try {
        #Send-SlackMessage -Uri $Env:SLACK_WEBHOOK_URI -Text "Cleaning: $($cihash[$key].vcenter)"

        $credential = Import-Clixml -Path $cihash[$key].secret

        $Env:GOVC_USERNAME = [System.Net.NetworkCredential]::new("", $credential).UserName
        $Env:GOVC_PASSWORD = [System.Net.NetworkCredential]::new("", $credential).Password

        Connect-VIServer -Server $cihash[$key].vcenter -Credential $credential | Out-Null


        #$storagePolicies = (Get-SpbmStoragePolicy | Where-Object -Property Name -Like "*ci*" | Where-Object -Property CreationTime -LT $deleteday )

        #foreach ($policy in $storagePolicies) {
        #    Remove-SpbmStoragePolicy -StoragePolicy $policy -Confirm:$false
        #}

        $govcOutput = "./volumes.json"
        $govcError = "./govcerror.txt"
        $process = Start-Process -Wait -RedirectStandardError $govcError -RedirectStandardOutput $govcOutput -FilePath /bin/govc -ArgumentList @("volume.ls", "-json", "-ds $($cihash[$key].datastore)") -PassThru

        if ($process.ExitCode -eq 0) {


            $volumeHash = (Get-Content -Path $govcOutput | ConvertFrom-Json -AsHashtable)

            Send-SlackMessage -Uri $Env:SLACK_WEBHOOK_URI -Text ($slackMessage -f $cihash[$key].vcenter, $volumeHash.Keys.Count)

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
        $caught = Get-Error
        $errStr = $caught.ToString()

        $caught

        Send-SlackMessage -Uri $Env:SLACK_WEBHOOK_URI -Text $errStr
        exit 1
    }
    finally {
        Disconnect-VIServer -Server * -Force:$true -Confirm:$false
    }
}

exit 0

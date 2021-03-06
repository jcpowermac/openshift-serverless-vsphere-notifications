#!/bin/pwsh

$Env:GOVC_URL = $Env:VCENTER_URI
$Env:GOVC_INSECURE = 1

try {
    $deleteday = (Get-Date).AddDays(-4)
    Send-SlackMessage -Uri $Env:SLACK_WEBHOOK_URI -Text "Cleaning: $($Env:VCENTER_URI)"

    Set-PowerCLIConfiguration -InvalidCertificateAction:Ignore -Confirm:$false | Out-Null
    Connect-VIServer -Server $Env:VCENTER_URI -Credential (Import-Clixml $Env:VCENTER_SECRET_PATH) | Out-Null

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

                $tag | Remove-Tag -Confirm:$False
                $tc | Remove-TagCategory -Confirm:$False
            }
            catch {}
        }
    }


    # Delete Storage Policies


    $storagePolicies = (Get-SpbmStoragePolicy | Where-Object -Property Name -Like "*ci*" | Where-Object -Property CreationTime -LT $deleteday )

    foreach ($policy in $storagePolicies) {
        Remove-SpbmStoragePolicy -StoragePolicy $policy -Confirm:$false
    }

    # Delete CNS Volumes

    # VMware is why we can't have nice things
    # This cmdlet is broke
    # $cnsVolumes = Get-CnsVolume

    $govcOutput = "./volumes.json"
    $govcError = "./govcerror.txt"
    $process = Start-Process -Wait -RedirectStandardError $govcError -RedirectStandardOutput $govcOutput -FilePath /bin/govc -ArgumentList @("volume.ls", "-json", "-ds $($Env:KUBEVOL_DATASTORE)") -PassThru

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

exit 0

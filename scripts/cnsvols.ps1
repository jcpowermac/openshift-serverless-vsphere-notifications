#!/bin/pwsh

. /var/run/config/vcenter/variables.ps1

Set-PowerCLIConfiguration -InvalidCertificateAction:Ignore -Confirm:$false | Out-Null
$cihash = ConvertFrom-Json -InputObject $ci -AsHashtable

# Function to send formatted Slack message
function Send-FormattedSlackMessage {
    param(
        [string]$Uri,
        [string]$Vcenter,
        [hashtable]$VolumeData
    )
    
    $totalVolumes = ($VolumeData.Values | Measure-Object -Sum).Sum
    $datastoreCount = $VolumeData.Count
    
    $message = @"
:package: *CNS Volumes Summary - $Vcenter*
Total Volumes: *$totalVolumes* | Datastores: *$datastoreCount*

*Datastore Breakdown:*
"@
    
    foreach ($ds in $VolumeData.Keys | Sort-Object) {
        $count = $VolumeData[$ds]
        $message += "`n• $ds`: $count volumes"
    }
    
    Send-SlackMessage -Uri $Uri -Text $message
}

foreach ($key in $cihash.Keys) {
    $credential = Import-Clixml -Path $cihash[$key].secret
    $vcenterData = @{}  # Store volume counts per datastore

    $Env:GOVC_PASSWORD = $credential.GetNetworkCredential().Password
    $Env:GOVC_USERNAME = $credential.GetNetworkCredential().UserName
    $Env:GOVC_URL = $cihash[$key].vcenter
    $Env:GOVC_INSECURE = 1

    try {
        Connect-VIServer -Server $cihash[$key].vcenter -Credential $credential | Out-Null

        $datacenters = Get-Datacenter

        foreach ($dc in $datacenters) {
            $Env:GOVC_DATACENTER = $dc.Name 

            write-host $dc.Name
            $datastores = Get-Datastore -Location $dc | Where-Object -Property Name -Like "vsan*"

            foreach ($ds in $datastores) {
                $govcOutput = "./volumes.json"
                $govcError = "./$($cihash[$key].vcenter)-$($ds.Name)-govcerror.txt"
                $govcOutdisk = "./$($cihash[$key].vcenter)-$($ds.Name)-govcoutdisk.txt"

                write-host $cihash[$key].vcenter
                write-host $ds.Name

                # the command below will reconcile datastore inventory which can get out of sync
                # the vSphere inventory of managed virtual disks can become temporarily out of synch with datastore disk backing metadata.
                # This problem can be due to a transient condition, such as an I/O error, or it can happen if a datastore is briefly inaccessible.
                # This problem has been observed only under stress testing.
                write-host "starting datastore clean up"
                Start-Process -Wait -FilePath /bin/govc -ArgumentList @("disk.ls", "-R", "-ds", $ds.Name) -ErrorAction Continue -RedirectStandardOutput $govcOutdisk
                write-host "DONE with datastore clean up"
       
                $process = Start-Process -Wait -RedirectStandardError $govcError -RedirectStandardOutput $govcOutput -FilePath /bin/govc -ArgumentList @("volume.ls", "-json", "-ds", $ds.Name) -PassThru -ErrorAction Continue

                if ($process.ExitCode -eq 0) {
                    $volumeHash = Get-Content -Path $govcOutput | ConvertFrom-Json 
                    #$volumeHash = (Get-Content -Path $govcOutput | ConvertFrom-Json -AsHashtable)
                    write-host "CV count" $volumeHash.Volume.Count
                    
                    # Store volume count for this datastore
                    $vcenterData[$ds.Name] = $volumeHash.Volume.Count

                    foreach ($vol in $volumeHash.volume) {
                        $volumeId = $vol.VolumeId.Id
                        $clusterId = $vol.Metadata.ContainerCluster.ClusterId
                        $clusterInventory = Get-Inventory -Name $clusterId -erroraction 'silentlycontinue'
                        if ($clusterInventory.Count -eq 0) {
                            Write-Host "Delete: $($volumeId)"
                            Start-Process -Wait -FilePath /bin/govc -ArgumentList @("volume.rm", $volumeId) -ErrorAction Continue
                        }
                        else {
                            write-host "$clusterId Alive"
                        }
                    }
                }
                else {
                    write-host "CNS Volume clean up didn't run for datastore $($ds.Name)"
                    Get-Content -Path $govcError
                }
            }
        }
        
        # Send consolidated message for this vCenter
        if ($vcenterData.Count -gt 0) {
            Send-FormattedSlackMessage -Uri $Env:SLACK_WEBHOOK_URI -Vcenter $cihash[$key].vcenter -VolumeData $vcenterData
        }
    }
    catch {
        $caught = Get-Error
        $errStr = $caught.ToString()
        $caught
        Send-SlackMessage -Uri $Env:SLACK_WEBHOOK_URI -Text ":x: *Error in CNS Volumes script for $($cihash[$key].vcenter):*`n$errStr"
    }
    finally {
        Disconnect-VIServer -Server * -Force:$true -Confirm:$false
    }
}
exit 0

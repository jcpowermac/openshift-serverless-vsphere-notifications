#!/bin/pwsh

. /var/run/config/vcenter/variables.ps1

Set-PowerCLIConfiguration -InvalidCertificateAction:Ignore -Confirm:$false | Out-Null

$cihash = ConvertFrom-Json -InputObject $ci -AsHashtable

$today = Get-Date

# Function to send formatted Slack message
function Send-FormattedSlackMessage {
    param(
        [string]$Uri,
        [hashtable]$KubevolData
    )
    
    $totalKubevols = ($KubevolData.Values | Measure-Object -Sum).Sum
    $vcenterCount = $KubevolData.Count
    
    $message = ":floppy_disk: *Kubernetes Volumes Summary*`n"
    $message += "Total Kubevols: *$totalKubevols* | vCenters: *$vcenterCount*`n`n"
    $message += "*Kubevol Count by vCenter:*`n"
    
    foreach ($vc in $KubevolData.Keys | Sort-Object) {
        $count = $KubevolData[$vc]
        $message += "`n• $vc`: $count kubevols"
    }
    
    Send-SlackMessage -Uri $Uri -Text $message
}

$kubevolData = @{}  # Store kubevol counts per vCenter

foreach ($key in $cihash.Keys) {
    $cihash[$key].vcenter
    try {
        Connect-VIServer -Server $cihash[$key].vcenter -Credential (Import-Clixml $cihash[$key].secret) | Out-Null

        $ds = Get-Datastore $cihash[$key].datastore

        $dsView = Get-View $ds.id

        $dsBrowser = Get-View $dsView.browser

        $flags = New-Object VMware.Vim.FileQueryFlags
        $flags.FileSize = $true
        $flags.FileType = $true
        $flags.Modification = $true

        $disk = New-Object VMware.Vim.VmDiskFileQuery
        $disk.details = New-Object VMware.Vim.VmDiskFileQueryFlags
        $disk.details.capacityKb = $true
        $disk.details.diskExtents = $true
        $disk.details.diskType = $true
        $disk.details.thin = $true

        $searchSpec = New-Object VMware.Vim.HostDatastoreBrowserSearchSpec
        $searchSpec.details = $flags
        $searchSpec.Query += $disk

        $rootKubeVolPath = "[" + $ds.Name + "]/kubevols"

        $kubevol = $dsBrowser.SearchDatastoreSubFolders($rootKubeVolPath, $searchSpec)

        # Store kubevol count for this vCenter
        $kubevolData[$cihash[$key].vcenter] = $kubevol[0].File.length

        $kubevol[0].File | Where-Object -Property Path -like "*.vmdk" | ForEach-Object {
            try {
                $voldate = [DateTime]$_.Modification

                $span = New-TimeSpan -Start $voldate -End $today

                if ($span.Days -ge 21) {
                    $deletePath = "$($rootKubeVolPath)/$($_.Path)"
                    Write-Host "deleting $($deletePath)"
                    $dsBrowser.DeleteFile($deletePath)
                }
            }
            catch {
                $caught = Get-Error
                $errStr = $caught.ToString()
                Send-SlackMessage -Uri $Env:SLACK_WEBHOOK_URI -Text ":x: *Error in Kubevols script for $($cihash[$key].vcenter):*`n$errStr"
            }
        }
    }
    catch {
        $caught = Get-Error
        $errStr = $caught.ToString()

        $caught

        Send-SlackMessage -Uri $Env:SLACK_WEBHOOK_URI -Text ":x: *Error in Kubevols script for $($cihash[$key].vcenter):*`n$errStr"
    }
    finally {
        Disconnect-VIServer -Server * -Force:$true -Confirm:$false
    }
}

# Send consolidated message for all vCenters
if ($kubevolData.Count -gt 0) {
    Send-FormattedSlackMessage -Uri $Env:SLACK_WEBHOOK_URI -KubevolData $kubevolData
}

exit 0

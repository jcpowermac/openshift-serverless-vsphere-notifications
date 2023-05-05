#!/bin/pwsh

. /var/run/config/vcenter/variables.ps1

Set-PowerCLIConfiguration -InvalidCertificateAction:Ignore -Confirm:$false | Out-Null

$cihash = ConvertFrom-Json -InputObject $ci -AsHashtable

$slackMessage = @"
Removing vmdk(s) from kubevols
vcenter: {0}
kubevols: {1}
"@

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


        $kubevol[0].File | Where-Object -Property Path -like "*.vmdk" | % {
            $voldate = [DateTime]$_.Modification

            $span = New-TimeSpan -Start $voldate -End $today

            if ($span.Days -ge 30) { 
                $deletePath = "$($rootKubeVolPath)/$($_.Path)"
                Write-Host "deleting $($deletePath)"
                $dsBrowser.DeleteFile($deletePath)
            }
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

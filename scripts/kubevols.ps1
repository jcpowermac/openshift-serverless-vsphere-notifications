#!/bin/pwsh

Set-PowerCLIConfiguration -InvalidCertificateAction:Ignore -Confirm:$false | Out-Null

foreach ($key in $cihash.Keys) {
    $cihash[$key].vcenter
    try {
        Send-SlackMessage -Uri $Env:SLACK_WEBHOOK_URI -Text "Cleaning Kubevols: $($cihash[$key].vcenter)"

        Connect-VIServer -Server $cihash[$key].vcenter -Credential (Import-Clixml $cihash[$key].secret) | Out-Null

        $deleteday = (Get-Date).AddDays(-4)

        $kubevols = Get-ChildItem (Get-Datastore $cihash[$key].datastore).DatastoreBrowserPath | Where-Object -Property FriendlyName -EQ "kubevols"
        $children = Get-ChildItem $kubevols.FullName | Where-Object -Property LastWriteTime -LT $deleteday

        foreach ($child in $children) {
            if ($child.Name.Contains("ci")) {
                Write-Output "$($child.Name) $($child.LastWriteTime)"
                Remove-Item -Confirm:$false $child.FullName -ErrorAction Continue
            }
        }
        foreach ($child in $children) {
            if ($child.Name.Contains("e2e")) {
                Write-Output "$($child.Name) $($child.LastWriteTime)"
                Remove-Item -Confirm:$false $child.FullName -ErrorAction Continue
            }
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

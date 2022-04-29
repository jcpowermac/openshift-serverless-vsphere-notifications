#!/bin/pwsh

$Env:GOVC_URL = $Env:VCENTER_URI
$Env:GOVC_INSECURE = 1

try {
    Send-SlackMessage -Uri $Env:SLACK_WEBHOOK_URI -Text "Cleaning Kubevols: $($Env:VCENTER_URI)"

    Set-PowerCLIConfiguration -InvalidCertificateAction:Ignore -Confirm:$false | Out-Null
    Connect-VIServer -Server $Env:VCENTER_URI -Credential (Import-Clixml $Env:VCENTER_SECRET_PATH) | Out-Null

    $deleteday = (Get-Date).AddDays(-4)

    $kubevols = Get-ChildItem (Get-Datastore $Env:KUBEVOL_DATASTORE).DatastoreBrowserPath | Where-Object -Property FriendlyName -EQ "kubevols"
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

exit 0

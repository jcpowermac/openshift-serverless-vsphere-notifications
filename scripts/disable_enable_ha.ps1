#!/bin/pwsh

. /var/run/config/vcenter/variables.ps1

Set-PowerCLIConfiguration -InvalidCertificateAction:Ignore -Confirm:$false | Out-Null

$cihash = ConvertFrom-Json -InputObject $ci -AsHashtable

# This script is to address this issue: https://communities.vmware.com/t5/VMware-vSphere-Discussions/vsphere-Ha-failover-operation-in-progress/td-p/1873093

$slackMessage = @"
vCenter Restart HA
vCenter: {0}
Cluster: {1}
"@

$errmessage = @"
vCenter: {0}
Error: {1}
"@

foreach ($key in $cihash.Keys) {
    $cihash[$key].vcenter

#if ($cihash[$key].vcenter -like "*ibmc.devcluster.openshift.com*") {

    try {

        Connect-VIServer -Server $cihash[$key].vcenter -Credential (Import-Clixml $cihash[$key].secret) | Out-Null
        
        # Get the cluster name
        #$clusterName = Get-Cluster -Server $cihash[$key].vcenter | Select-Object -First 1 | Select-Object Name

        # Disable VMware HA
        Set-Cluster -Cluster $cihash[$key].cluster -HAEnabled $false -Confirm:$false
        #Set-Cluster -Cluster $clusterName.Name -HAEnabled $false -Confirm:$false


        # Wait 120 seconds
        Start-Sleep -Seconds 120

        # Enable VMware HA
        Set-Cluster -Cluster $cihash[$key].cluster -HAEnabled $true -Confirm:$false
        #Set-Cluster -Cluster $clusterName.Name -HAEnabled $true -Confirm:$false

        $cihash[$key].cluster
        #$clusterName.Name
       
        # we don't need messages unless its broke...
        #Send-SlackMessage -Uri $Env:SLACK_WEBHOOK_URI -Text ($slackMessage -f $cihash[$key].vcenter, $vm.Count, $tag.Count)

    }
    catch {
        $caught = Get-Error
        $errStr = $caught.ToString()

        $caught


        Send-SlackMessage -Uri $Env:SLACK_WEBHOOK_URI -Text ($errmessage -f $cihash[$key].vcenter, $errStr)
        exit 1
    }
    finally {
        Disconnect-VIServer -Server * -Force:$true -Confirm:$false
    }
#}
}

exit 0

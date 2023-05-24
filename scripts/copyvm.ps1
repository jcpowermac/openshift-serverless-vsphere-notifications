#!/bin/pwsh
. /var/run/config/vcenter/variables.ps1

Set-PowerCLIConfiguration -DefaultVIServerMode Multiple -InvalidCertificateAction:Ignore -Confirm:$false | Out-Null
$cihash = ConvertFrom-Json -InputObject $ci -AsHashtable

$folderName = "windows-golden-images"
$vmname = "windows-server-2022-template-ipv6-disabled-with-docker"


try {   
    $computeClusterName = "Cluster-1"
    $datastoreName = "WorkloadDatastore"
    $key = "vmc"
    Connect-VIServer -Server $cihash[$key].vcenter -Credential (Import-Clixml $cihash[$key].secret) | Out-null 

    $folder = Get-Folder -Name $folderName 


    if (-Not (Test-Path -Path "$($vmname).ova")) {
        $vm = Get-vm -Name $vmname -location $folder -erroraction continue
        if (-Not $?) {
            $computeCluster = Get-Cluster $computeClusterName 
            $datastore = Get-datastore $datastoreName 

            $template = get-template -name $vmname -location $folder 

            $vm = New-VM -Name "$($vmname)-temp" -Template $template -ResourcePool $computeCluster -Datastore $datastore  -location $folder 
        }
        $vm | Export-VApp -Destination "$($vmname).ova" -Format OVA
    }
}
catch { 
    get-error 
}
finally {
    Disconnect-VIServer -Server * -Force:$true -Confirm:$false
}



try {
    $portgroup = "dev-ci-workload-1"
    $computeClusterName = "vcs-ci-workload"
    $datacenterName = "IBMCloud"
    $datastoreName = "vsanDatastore"

    $key = "ibm"
    Connect-VIServer -Server $cihash[$key].vcenter -Credential (Import-Clixml $cihash[$key].secret) | Out-null 

    $datacenter = Get-Datacenter -Name $datacenterName
    $datastore = Get-Datastore   -Name $datastoreName -Location $datacenter
    $computeCluster = Get-Cluster $computeClusterName 
    $vmhost = Get-Random -InputObject (Get-VMHost  -Location (Get-Cluster -name $computeCluster))

    $vmhost

    $ovfConfig = Get-OvfConfiguration -Ovf "$($vmname).ova"
    $ovfConfig.NetworkMapping.dev_segment.Value = $portgroup

    $folder = Get-Folder  -Name $folderName -Location (Get-Folder  -Name vm -Location $datacenter)

    $vapp = Import-Vapp -Source "$($vmname).ova" -Name $vmname -OvfConfiguration $ovfConfig -VMHost $vmhost -Datastore $datastore -InventoryLocation $folder -Force:$true

        

}
catch { 
    get-error 
}
finally {
    Disconnect-VIServer -Server * -Force:$true -Confirm:$false
}
exit 0
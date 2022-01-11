#!/bin/pwsh

try {
    Set-PowerCLIConfiguration -InvalidCertificateAction:Ignore -Confirm:$false | Out-Null
    Connect-VIServer -Server $Env:VCENTER_URI -Credential (Import-Clixml $Env:VCENTER_SECRET_PATH) | Out-Null

    $folders = get-folder | Where-Object {$_.IsChildTypeVm -eq $true}
    foreach ($f in $folders) {
        $length = (($f | get-view).ChildEntity.Length)
        if ($length -eq 0) {
            try {
                $f | remove-folder -DeletePermanently -Confirm:$false

                $tag = Get-Tag -Name $f.Name
                $tc = Get-TagCategory -Name $tag.Category

                Write-Host "Removing Tag: $($tag.Name), Removing TagCategory: $($tc.Name), Remove Folder: $($f.Name)"

                $tag | Remove-Tag -Confirm:$False
                $tc | Remove-TagCategory -Confirm:$False
            }
            catch{}
        }
    }
    $resourcePools = Get-ResourcePool | Where-Object { $_.Name -match 'ci' }

    foreach ($rp in $resourcePools) {
        [array]$resourcePoolVirtualMachines = $rp | Get-VM
        if ($resourcePoolVirtualMachines.Length -eq 0) {
            Write-Host "Remove RP: $($rp.Name)"
		    remove-resourcepool -ResourcePool $rp -Confirm:$false
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

#!/bin/pwsh

. /var/run/config/vcenter/variables.ps1

Set-PowerCLIConfiguration -InvalidCertificateAction:Ignore -Confirm:$false | Out-Null

$cihash = ConvertFrom-Json -InputObject $ci -AsHashtable

$slackMessage = @"
Removing orphan virtual machines(s)
vcenter: {0}
virtual machines: {1}
"@


$slackMessageVirtualMachines = @()

foreach ($key in $cihash.Keys) {
    $cihash[$key].vcenter
    try {

        Connect-VIServer -Server $cihash[$key].vcenter -Credential (Import-Clixml $cihash[$key].secret) | Out-Null

        $virtualMachines = @(Get-VM | Where-Object { $_.Name -match '^ci-*' })

        foreach ($vm in $virtualMachines) {
            if ($vm.PowerState -eq 'PoweredOff') { 
                $disks = Get-harddisk -VM $vm


                foreach ($d in $disks) {
                    if ($d.CapacityGB -eq 0) {
                        $d | Remove-HardDisk -DeletePermanently:$false -Confirm:$false

                        Remove-VM -VM $vm -DeletePermanently:$true -Confirm:$false
                        
                        $slackMessageVirtualMachines += $vm.Name
                        break
                    }
                }
            }
        }


        if ($slackMessageVirtualMachines.Count -gt 0 ) {
            $vmsMessage =  $slackMessageVirtualMachines -join ","
            Send-SlackMessage -Uri $Env:SLACK_WEBHOOK_URI -Text ($slackMessage -f $cihash[$key].vcenter,$vmsMessage)
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

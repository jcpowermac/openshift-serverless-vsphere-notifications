#!/bin/pwsh
. /var/run/config/vcenter/variables.ps1

Set-PowerCLIConfiguration -InvalidCertificateAction:Ignore -Confirm:$false | Out-Null
$cihash = ConvertFrom-Json -InputObject $ci -AsHashtable
$slackMessage = @"
Removing storage policies
vcenter: {0}
storage policies: {1}
"@

#$deleteday = (Get-Date).AddDays(-4)
foreach ($key in $cihash.Keys) {
    #$policyToRemove = @{}


    try {
        $cihash[$key].vcenter
        $cihash[$key].datacenter
        $cihash[$key].cluster
        $cihash[$key].datastore

        Connect-VIServer -Server $cihash[$key].vcenter -Credential (Import-Clixml $cihash[$key].secret) | Out-Null

        $storagePolicies = Get-SpbmStoragePolicy 
        Send-SlackMessage -Uri $Env:SLACK_WEBHOOK_URI -Text ($slackMessage -f $cihash[$key].vcenter, $storagePolicies.Count)

        foreach ($policy in $storagePolicies) {

            $clusterId = ($policy.Name -split "openshift-storage-policy-")[1]

            if(-not($clusterId)) {
                $clusterInventory = Get-Inventory -Name $clusterId -ErrorAction Continue
                Write-Host $clusterId

                if ($clusterInventory.Count -eq 0) {
                    Write-Host "Removing vSan File share: $($fs.Id)"
                    $fs | Remove-VsanFileShare -Confirm:$false -Force:$true
                } 
                else {
                    Write-Host "not deleting: $($clusterInventory)"
                }
            }
        }


            #if ($policy.Name.Contains("ci")) {
            #    if (!$policyToRemove.ContainsKey($policy.Name)) {
            #            $policyToRemove.Add($policy.Name, $policy)
            #        }
            #    }

            #    foreach ($ruleset in $policy.AnyOfRuleSets) {
            #        if ($ruleset.AllOfRules.AnyOfTags.IsTagMissing) {
            #            if (!$policyToRemove.ContainsKey($policy.Name)) {
            #                    $policyToRemove.Add($policy.Name, $policy)
            #                }
            #            }
            #        }
            #    }
            #    foreach ($policyKey in $policyToRemove.Keys) {
            #        Remove-SpbmStoragePolicy -StoragePolicy $policyToRemove[$policyKey] -Confirm:$false -ErrorAction Continue
            #    }

            #}

    } 
    catch {
        $caught = Get-Error
        $errStr = $caught.ToString()
        $caught
        Send-SlackMessage -Uri $Env:SLACK_WEBHOOK_URI -Text $errStr
    }
    finally {
        Disconnect-VIServer -Server * -Force:$true -Confirm:$false
    }
}

exit 0

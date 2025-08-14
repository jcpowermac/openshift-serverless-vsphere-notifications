#!/bin/pwsh
. /var/run/config/vcenter/variables.ps1

Set-PowerCLIConfiguration -InvalidCertificateAction:Ignore -Confirm:$false | Out-Null
$cihash = ConvertFrom-Json -InputObject $ci -AsHashtable

# Function to send formatted Slack message
function Send-FormattedSlackMessage {
    param(
        [string]$Uri,
        [hashtable]$PolicyData
    )
    
    $totalPolicies = ($PolicyData.Values | Measure-Object -Sum).Sum
    $vcenterCount = $PolicyData.Count
    
    $message = @"
:gear: *Storage Policy Summary*
Total Policies: *$totalPolicies* | vCenters: *$vcenterCount*

*Policy Count by vCenter:*
"@
    
    foreach ($vc in $PolicyData.Keys | Sort-Object) {
        $count = $PolicyData[$vc]
        $message += "`n• $vc`: $count policies"
    }
    
    Send-SlackMessage -Uri $Uri -Text $message
}

$policyData = @{}  # Store policy counts per vCenter

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
        $policyData[$cihash[$key].vcenter] = $storagePolicies.Count

        foreach ($policy in $storagePolicies) {

            $clusterInventory = @()
            $splitResults = @($policy.Name -split "openshift-storage-policy-")

            if ($splitResults.Count -eq 2) {
                $clusterId = $splitResults[1]
                if ($clusterId -ne "") {
                    Write-Host $clusterId
                    $clusterInventory = @(Get-Inventory -Name "$($clusterId)*" -ErrorAction Continue)

                    if ($clusterInventory.Count -eq 0) {
                        Write-Host "Removing policy: $($policy.Name)"
                        $policy | Remove-SpbmStoragePolicy -Confirm:$false
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
    }
    catch {
        $caught = Get-Error
        $errStr = $caught.ToString()
        $caught
        Send-SlackMessage -Uri $Env:SLACK_WEBHOOK_URI -Text ":x: *Error in Storage Policy script for $($cihash[$key].vcenter):*`n$errStr"
    }
    finally {
        Disconnect-VIServer -Server * -Force:$true -Confirm:$false
    }
}

# Send consolidated message for all vCenters
if ($policyData.Count -gt 0) {
    Send-FormattedSlackMessage -Uri $Env:SLACK_WEBHOOK_URI -PolicyData $policyData
}

exit 0

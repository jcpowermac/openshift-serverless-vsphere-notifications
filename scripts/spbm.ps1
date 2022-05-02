#!/bin/pwsh
. /var/run/config/vcenter/variables.ps1

Set-PowerCLIConfiguration -InvalidCertificateAction:Ignore -Confirm:$false | Out-Null
$cihash = ConvertFrom-Json -InputObject $ci -AsHashtable
$slackMessage = @"
Removing storage policies
vcenter: {0}
storage policies: {1}
"@

$deleteday = (Get-Date).AddDays(-4)
foreach ($key in $cihash.Keys) {
    $policyToRemove = @{}
    try {
        $cihash[$key].vcenter
        $cihash[$key].datacenter
        $cihash[$key].cluster
        $cihash[$key].datastore

        Connect-VIServer -Server $cihash[$key].vcenter -Credential (Import-Clixml $cihash[$key].secret) | Out-Null

        $storagePolicies = @(Get-SpbmStoragePolicy | Where-Object -Property CreationTime -LT $deleteday)
        Send-SlackMessage -Uri $Env:SLACK_WEBHOOK_URI -Text ($slackMessage -f $cihash[$key].vcenter, $storagePolicies.Count)

        foreach ($policy in $storagePolicies) {
            if ($policy.Name.Contains("ci")) {
                if (!$policyToRemove.ContainsKey($policy.Name)) {
                        $policyToRemove.Add($policy.Name, $policy)
                    }
                }

                foreach ($ruleset in $policy.AnyOfRuleSets) {
                    if ($ruleset.AllOfRules.AnyOfTags.IsTagMissing) {
                        if (!$policyToRemove.ContainsKey($policy.Name)) {
                                $policyToRemove.Add($policy.Name, $policy)
                            }
                        }
                    }
                }
                foreach ($policyKey in $policyToRemove.Keys) {
                    Remove-SpbmStoragePolicy -StoragePolicy $policyToRemove[$policyKey] -Confirm:$false -ErrorAction Continue
                }
            }
            catch {
                Get-Error
            }
            finally {
                Disconnect-VIServer -Server * -Force:$true -Confirm:$false
            }
        }

        exit 0

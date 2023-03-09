#!/bin/pwsh
. /var/run/config/vcenter/variables.ps1

Set-PowerCLIConfiguration -InvalidCertificateAction:Ignore -Confirm:$false | Out-Null
$cihash = ConvertFrom-Json -InputObject $ci -AsHashtable
$slackMessage = @"
Removing Folders and Tags
vcenter: {0}
folders: {1}
tags: {2}
"@

foreach ($key in $cihash.Keys) {
    $tagCategoriesToRemove = @{}
    $tagsToRemove = @{}
    $cihash[$key].vcenter
    $cihash[$key].datacenter
    $cihash[$key].cluster
    $cihash[$key].datastore

    try {
        Connect-VIServer -Server $cihash[$key].vcenter -Credential (Import-Clixml $cihash[$key].secret) | Out-Null

        #Write-Host "Get-TagAssignment is slow..."
        # Looks like this doesn't work in VMC
        #$tagAssignments = @(Get-TagAssignment -ErrorAction Continue)
        #$tags = @(Get-Tag | Where-Object { $_.Name -match '^ci*|^qeci*' })
        $tags = @(Get-Tag)
        $folders = @(Get-Folder | Where-Object { $_.IsChildTypeVm -eq $true })
        $virtualMachines = @(Get-VM | Where-Object { $_.Name -match '^ci*|^qeci*' })

        Send-SlackMessage -Uri $Env:SLACK_WEBHOOK_URI -Text ($slackMessage -f $cihash[$key].vcenter, $folders.Length, $tags.Length)

        foreach ($f in $folders) {
            $length = (($f | Get-View).ChildEntity.Length)

            if ($f.Name -eq "debug") {
                continue
            }

            if ($length -eq 0) {
                $f.Name
                $f | Remove-Folder -DeletePermanently -Confirm:$false -ErrorAction Continue
            }
        }

        foreach ($tag in $tags) {
            #$selectedAssignment = @($tagAssignments | Where-Object { $_.Tag.Name -eq $tag.Name })

            $selectedVirtualMachines = @($virtualMachines | Where-Object {$_.Name.StartsWith($tag.Name)})

            # revisit this later...
            # since in vmc we cannot get tag assignments this will always be 0

            #if ( $selectedAssignment.Count -le 1) {
            #    if(!$tagsToRemove.ContainsKey($tag.Name)) {
            #        $tagsToRemove.Add($tag.Name, $tag)
            #    }

            #    if(!$tagCategoriesToRemove.ContainsKey($tag.Category.Name)) {
            #        $tagCategoriesToRemove.Add($tag.Category.Name, $tag.Category)
            #    }
            #}

            if($selectedVirtualMachines.Count -eq 0) {
                if(!$tagsToRemove.ContainsKey($tag.Name)) {
                    $tagsToRemove.Add($tag.Name, $tag)
                }
                if(!$tagCategoriesToRemove.ContainsKey($tag.Category.Name)) {
                    $tagCategoriesToRemove.Add($tag.Category.Name, $tag.Category)
                }
            }
        }

        foreach ($tagKey in $tagsToRemove.Keys) {
            Remove-Tag -Tag $tagsToRemove[$tagKey] -Confirm:$false -ErrorAction Continue
        }
        foreach ($tagCatKey in $tagCategoriesToRemove.Keys) {
            Remove-TagCategory -Category $tagCategoriesToRemove[$tagCatKey] -Confirm:$false -ErrorAction Continue
        }
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

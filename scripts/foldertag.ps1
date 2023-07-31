
#!/bin/pwsh

# Set-PSDebug -Trace 1

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


        # All the tags attached to the current virtual machines.
        $tagAssignments = @(Get-TagAssignment -Entity (get-vm) -ErrorAction Continue)
        $tags = @(Get-Tag)
        $tagCategories = @(Get-TagCategory)
        $folders = @(Get-Folder | Where-Object { $_.IsChildTypeVm -eq $true })

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

        # loop through all the tags
        foreach ($tag in $tags) {

            # skip zonal tags
            if($tag.Name.StartsWith("us-")) {
                continue
            }

            # from get-tagassignment select all the virtual machines with tag
            # if assignment does not exist Count will be 0
            # if assignment exists Count must be less than or equal to 1 to remove.
            $selectedAssignment = @($tagAssignments | Where-Object { $_.Tag.Name -eq $tag.Name })


            if ( $selectedAssignment.Count -le 1) {
                if(!$tagsToRemove.ContainsKey($tag.Name)) {

                    $tag.Name
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


        foreach($c in $tagCategories) {
            $findTags = @(Get-tag -Category $c)
            if($findTags.Count -eq 0) {
                $c | Remove-TagCategory -Confirm:$false -ErrorAction Continue
            }
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


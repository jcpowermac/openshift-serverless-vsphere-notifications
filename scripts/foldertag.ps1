
#!/bin/pwsh

# Set-PSDebug -Trace 1

. /var/run/config/vcenter/variables.ps1

Set-PowerCLIConfiguration -InvalidCertificateAction:Ignore -Confirm:$false | Out-Null
$cihash = ConvertFrom-Json -InputObject $ci -AsHashtable

# Function to send formatted Slack message
function Send-FormattedSlackMessage {
    param(
        [string]$Uri,
        [hashtable]$FolderData,
        [hashtable]$TagData
    )
    
    $totalFolders = ($FolderData.Values | Measure-Object -Sum).Sum
    $totalTags = ($TagData.Values | Measure-Object -Sum).Sum
    $vcenterCount = $FolderData.Count
    
    $message = ":file_folder: *Folder and Tag Cleanup Summary*`n"
    $message += "Total Folders: *$totalFolders* | Total Tags: *$totalTags* | vCenters: *$vcenterCount*`n`n"
    $message += "*Counts by vCenter:*`n"
    
    foreach ($vc in $FolderData.Keys | Sort-Object) {
        $folderCount = $FolderData[$vc]
        $tagCount = $TagData[$vc]
        $message += "`n• $vc`: $folderCount folders, $tagCount tags"
    }
    
    Send-SlackMessage -Uri $Uri -Text $message
}

$folderData = @{}  # Store folder counts per vCenter
$tagData = @{}     # Store tag counts per vCenter

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

        # Store counts for this vCenter
        $folderData[$cihash[$key].vcenter] = $folders.Length
        $tagData[$cihash[$key].vcenter] = $tags.Length

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

        Send-SlackMessage -Uri $Env:SLACK_WEBHOOK_URI -Text ":x: *Error in Folder/Tag script for $($cihash[$key].vcenter):*`n$errStr"
    }
    finally {
        Disconnect-VIServer -Server * -Force:$true -Confirm:$false
    }
}

# Send consolidated message for all vCenters
if ($folderData.Count -gt 0) {
    Send-FormattedSlackMessage -Uri $Env:SLACK_WEBHOOK_URI -FolderData $folderData -TagData $tagData
}

exit 0


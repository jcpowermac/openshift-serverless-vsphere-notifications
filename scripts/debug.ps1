#!/bin/pwsh

try {

    Set-PowerCLIConfiguration -InvalidCertificateAction:Ignore -Confirm:$false | Out-Null

    Connect-VIServer -Server $Env:VCENTER_URI -Credential (Import-Clixml $Env:VCENTER_SECRET_PATH) | Out-Null

    # CI has moved virtual machines to the debug folder we better take a look
    #
    #
    $debugFolder = get-folder -Name Debug

    if ($?) {
       Get-VM -Location $debugFolder | %{
           $events = Get-VIEvent -Entity $_
           $events >> "/var/log/debug/$($_.Name).txt"

           $events | Select-Object -Property FullFormattedMessage
       }

       # if($debugVirtualMachines.Count -gt 0) {
       #     $debugVMSlackMsg = ":fire: VMs in debug folder: $($debugVirtualMachines -join ',')"
       #     Send-SlackMessage -Uri $Env:SLACK_WEBHOOK_URI -Text $debugVMSlackMsg
       # }
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

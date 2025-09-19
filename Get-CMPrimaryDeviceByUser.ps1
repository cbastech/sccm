
<#
.SYNOPSIS
    Retrieves the primary device(s) for a given user, or the members of a given Active Directory Group,
    based on user affinity / usage time.

.PARAMETER UserName
    (Position = 0) The username of the target individual. This is the default mode of the script.

.PARAMETER ShowStatus
    (Switch) If set, includes the Enabled status of the user's account (True/False)

.PARAMETER GroupName
    If set, directs the script to search for the members of the specified Active Directory group instead of a single user.

.EXAMPLE
Get-CMPrimaryDeviceByUser joe.smith

SamAccountName Computer
-------------- --------
joe.smith      {VM00123}

.EXAMPLE
Get-CMPrimaryDeviceByUser "Doc Brown" -ShowStatus

SamAccountName Enabled Computer
-------------- ------- --------
doc.brown      True     {DESKTOP998, LAPTOP8679}

.EXAMPLE
Get-CMPrimaryDeviceByUser -GroupName Sales_Laptop_Users

SamAccountName  Computer
--------------  --------
doc.brown       SALES-1292
samuel.cartman  SALES-1162
bugs.bunny      SALES-1144
egon.spengler   SALES-0018
rose.nylund     SALES-1145

.NOTES
Run this while connected to the SCCM Site via Powershell.
This function requires the Active Directory Powershell module to be available.

#>

function Get-CMPrimaryDeviceByUser {
    [CmdletBinding(DefaultParameterSetName = 'User')]
    param(
        [Parameter(Mandatory, ParameterSetName="User", Position=0)]
        [string]$UserName,
        
        [Parameter(ParameterSetName="User")]
        [switch]$ShowStatus,
    
        [Parameter(Mandatory, ParameterSetName="Group")]
        [string]$GroupName
    )

    # What domain are we on? 

    $domain = (Get-ADDomain).Name
         
    if ($UserName) {
        try {
            $samaccountname = (Get-ADUser -Identity "$UserName" | select-object SamAccountName).SamAccountName
        }
        catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException] {
            $UserName = $Username -replace (" ",".")
            $samaccountname = (Get-ADUser -Identity $UserName | select-object SamAccountName).SamAccountName 
        }
    }
        
    if ($GroupName) { 
        try { 
            $groupexists = Get-ADGroup -Identity $GroupName
        }
        catch {
            Write-Host $_ -Foreground Red
        }
    }

    if ($SamAccountName) {
        if ($ShowStatus) {
            $results = (Get-ADUser -Identity $SamAccountName | Select-Object -Property SamAccountName, Enabled, @{name='Computer'; expression={Get-CMUserDeviceAffinity -UserName "$($Domain)\$($_.SamAccountName)" `
            | Where-Object {$_.Sources -contains '4'} | Foreach-Object { Get-CMDevice -fast -ResourceId $_.ResourceID | Select-Object -ExpandProperty Name }
            } # End 'Expression'
            } # End Custom properties (@)
            )
        } #End ShowStatus
        else {
            $results = (Get-ADUser -Identity $SamAccountName | Select-Object -Property SamAccountName, @{name='Computer'; expression={Get-CMUserDeviceAffinity -UserName "$($Domain)\$($_.SamAccountName)" `
            | Where-Object {$_.Sources -contains '4'} | Foreach-Object { Get-CMDevice -fast -ResourceId $_.ResourceID | Select-Object -ExpandProperty Name }
            } # End 'Expression'
            } # End Custom properties (@)
            )
        } #End ShowStatus
    } #End SamAccountName
    
    if ($GroupExists) {
    
        # For the 'Sources'
        # https://learn.microsoft.com/en-us/mem/configmgr/develop/reference/core/clients/manage/sms_usermachinerelationship-server-wmi-class#properties	


        $results = (Get-ADGroupMember $GroupName `
            | Select-Object -property SamAccountName, @{name='Computer'; expression={Get-CMUserDeviceAffinity -UserName "$($Domain)\$($_.SamAccountName)" `
            | Where-Object {$_.Sources -contains '4'} | Foreach-Object { Get-CMDevice -fast -ResourceId $_.ResourceID | Select-Object -ExpandProperty Name }
            } # End 'Expression'
            } # End Custom properties (@)
        )
    
    
    } # End GroupExists

    return $results  
    
} # End Function
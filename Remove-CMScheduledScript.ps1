function Remove-CMScheduledScript {
        <#
        .SYNOPSIS
        Attempts to retrieve and delete Scheduled Script deployments from the Microsoft Configuration Manager database.

        .DESCRIPTION
        Connects to the Microsoft Configuration Manager SQL server/database and attempts to locate the specified scheduled script deployments.  If found, the script will request confirmation before attempting to delete the deployment. 

        .PARAMETER ScheduleID
        The GUID identifier of the scheduled script deployment.  This can be found in the Configuration Manager GUI under Monitoring > Scheduled Scripts in the 'DeploymentID' column. Aliased to 'DeploymentID'.

        .PARAMETER InputObject
        A System.Data.DataRow object representing a scheduled script deployment.  

        .PARAMETER SCCMSQLServer
        The hostname of the SCCM SQL Database server.  Does not have to be fully qualified.

        .PARAMETER DBName
        The database name for the SCCM database.

        .INPUTS
        System.Data.DataRow

        .OUTPUTS
        None.

        .EXAMPLE
        PS> Remove-pcCMScheduledScript -ScheduleID a6367634-6c46-4a2a-abb2-54370b053afe
        Found matching scheduled script deployment:


        ScheduleId        : a6367634-6c46-4a2a-abb2-54370b053afe
        ScriptGuid        : d676c633-f80b-4531-91af-849df1d019bf
        ScriptName        : test.script
        ClientOperationId :
        CollectionId      : ABC00D0B
        CollectionName    : test.device.collection
        ProcessedState    : 0
        CreatedTime       : 5/23/2025 3:22:44 PM
        ScheduleTime      : 5/24/2025 3:22:36 PM


        Confirm Delete
        Are you sure you want to delete this deployment?
        [Y] Yes  [A] Yes to All  [N] No  [L] No to All  [S] Suspend  [?] Help (default is "N"): y
        Scheduled script deployment has been deleted.

        .EXAMPLE
        PS> Remove-pcCMScheduledScript -InputObject $object
        Found matching scheduled script deployment:


        ScheduleId        : a6367634-6c46-4a2a-abb2-54370b053afe
        ScriptGuid        : d676c633-f80b-4531-91af-849df1d019bf
        ScriptName        : test.script
        ClientOperationId :
        CollectionId      : ABC00D0B
        CollectionName    : test.device.collection
        ProcessedState    : 0
        CreatedTime       : 5/23/2025 3:22:44 PM
        ScheduleTime      : 5/24/2025 3:22:36 PM


        Confirm Delete
        Are you sure you want to delete this deployment?
        [Y] Yes  [A] Yes to All  [N] No  [L] No to All  [S] Suspend  [?] Help (default is "N"): y
        Scheduled script deployment has been deleted.

        .LINK
        Get-pcCMScheduledScript
    #>

    [CmdletBinding(SupportsShouldProcess,DefaultParameterSetName="StringInput")]
    param(
    [Parameter(ParameterSetName="StringInput",
    Mandatory=$true,
    ValueFromPipeline = $false)]
    [Alias("DeploymentID")]
    [string]$ScheduleID,
    [Parameter(ParameterSetName="ObjectInput",
    Mandatory=$true,
    ValueFromPipeline = $true)]
    [object]$InputObject,
    [Parameter(Mandatory=$true,
    ParameterSetName="StringInput")]
    [Parameter(Mandatory=$true,
    ParameterSetName="ObjectInput")]
    [string]$SCCMSQLServer,
    [Parameter(Mandatory=$true,
    ParameterSetName="StringInput")]
    [Parameter(Mandatory=$true,
    ParameterSetName="ObjectInput")]
    [string]$DBName
    )

    begin {

        # Import MECM Powershell Module
        $CMModulePath = $Env:SMS_ADMIN_UI_PATH.ToString().Substring(0,$Env:SMS_ADMIN_UI_PATH.Length -  5)+"\ConfigurationManager.psd1"

        Import-Module $CMModulePath

        if (-not (Get-Module -Name ConfigurationManager)) {
                Write-Log "Import-Module for 'ConfigurationManager.psdl' failed.  Script cannot continue."
            exit 1
        }

        Try {
            $SQLConnection = New-Object System.Data.SQLClient.SQLConnection
            $SQLConnection.ConnectionString ="server=$SCCMSQLSERVER;database=$DBNAME;Integrated Security=$true;"
            $SQLConnection.Open()
        } catch {
            return $error[0]
        }
    }

    process {

        if ($InputObject) {
            $ScheduleID = $InputObject.ScheduleID.Guid
            if (-not $ScheduleID) {
                return "Error: Input object is not a valid Scheduled Script deployment object."
            }
        }

        $SQLCommand = New-Object System.Data.SqlClient.SqlCommand

        $SQLCommand.Connection = $SQLConnection

        $SQLAdapter = New-Object System.Data.SqlClient.SqlDataAdapter

        # No parameters?  Get everything
        if ($PSBoundParameters.Count -eq 0) {
            return 
        }
        else {
            # Sanity check. Word characters only until Microsoft gives us an actual professional module
            if ($ScheduleID -match "[^a-zA-Z_0-9\-\.]") {
                return "Parameter value may only contain letters, numbers, underscore, hyphen, and periods."     
            }

            # Selection
            $SQLCommand.CommandText = "SELECT * FROM dbo.vSMS_ScheduleScripts WHERE ScheduleID = '$ScheduleID'"
            $SqlAdapter.SelectCommand = $SQLCommand
        }

        $SQLDataset = New-Object System.Data.DataSet

        try {
            $SqlAdapter.fill($SQLDataset) | out-null
        } catch {
            return $error[0]
        }

        if ($SQLDataSet.tables.rows) { 
            Write-Output "Found matching scheduled script deployment:"
            Write-Output $SQLDataSet.tables
            $yesToAll = $false
            $noToAll = $false
            if ($PSCmdlet.ShouldContinue("Are you sure you want to delete this deployment?","Confirm Delete",$true,[ref]$yesToAll,[ref]$noToAll)) {           
                # Deletion
                $SQLCommand.CommandText = "DELETE FROM dbo.vSMS_ScheduleScripts WHERE ScheduleID = '$ScheduleID'"
                $sqlAdapter.DeleteCommand = $SQLCommand

                # Sanity catch
                $SQLCommand = $null
                $SqlAdapter.fill($SQLDataset) | Out-Null
                Write-Output "Scheduled script deployment has been deleted."
            }
        }
        else { 
            return "No scheduled script deployment for ScheduleID `"$ScheduleID`"."
        }
    }

    end {
        $SQLConnection.Close()
    }
}

function Get-CMScheduledScript {

        <#
        .SYNOPSIS
        Retrieves Scheduled Script deployments from the Microsoft Configuration Manager database.

        .DESCRIPTION
        Connects to the Microsoft Configuration Manager SQL server/database and attempts to locate scheduled script deployments, based on either Script Name or ScheduleID (called 'DeploymentID' in the Configuration Manager GUI).  This will include both historical and future deployments. 
        
        If neither 'ScheduledID' nor 'ScriptName' parameter are included, the commandlet will return all scheduled script objects present in the database.

        .PARAMETER ScheduleID
        The GUID identifier of the scheduled script deployment.  This can be found in the Configuration Manager GUI under Monitoring > Scheduled Scripts in the 'DeploymentID' column. Note that searching by ScheduledID will return one and only one unique deployment.

        Aliased to 'DeploymentID'.

        .PARAMETER ScriptName
        The script name of the target script. Searching by script name will return all deployments, past and future, of the target script.

        .PARAMETER SCCMSQLServer
        The hostname of the SCCM SQL Database server.  Does not have to be fully qualified.

        .PARAMETER DBName
        The database name for the SCCM database.  

        .INPUTS
        This commandlet does not accept object inputs.

        .OUTPUTS
        System.Data.DataRow

        .EXAMPLE
        PS> Get-pcCMScheduledScript -ScheduleID <DeploymentID>

        ScheduleId        : a6367634-6c46-4a2a-abb2-54370b053afe
        ScriptGuid        : d676c633-f80b-4531-91af-849df1d019bf
        ScriptName        : test.script
        ClientOperationId :
        CollectionId      : ABC00D0B
        CollectionName    : test.device.collection
        ProcessedState    : 0
        CreatedTime       : 5/23/2025 3:22:44 PM
        ScheduleTime      : 5/24/2025 3:22:36 PM

        .EXAMPLE
        PS> Get-pcCMScheduledScript -ScriptName <ScriptName>

        ScheduleId        : a6367634-6c46-4a2a-abb2-54370b053afe
        ScriptGuid        : d676c633-f80b-4531-91af-849df1d019bf
        ScriptName        : test.script
        ClientOperationId :
        CollectionId      : ABC00D0B
        CollectionName    : test.device.collection
        ProcessedState    : 0
        CreatedTime       : 5/23/2025 3:22:44 PM
        ScheduleTime      : 5/24/2025 3:22:36 PM

        .NOTES
        There doesn't seem to be a way to do this without an explicit connection into the database. While there are WMI/CIM
        classes for scripts, none of them contain information about scheduled scripts.
    #>


    [CmdletBinding(DefaultParameterSetName="ByScheduleID")]
    param(
    [Parameter(Mandatory=$false,
    ParameterSetName="ByScheduleID")]
    [Alias("DeploymentID")]
    [string]$ScheduleID,
    [Parameter(Mandatory=$false,
    ParameterSetName="ByScriptName")]
    [Alias("Name")]
    [string]$ScriptName,
    [Parameter(Mandatory=$true,
    ParameterSetName="ByScriptName")]
    [Parameter(Mandatory=$true,
    ParameterSetName="ByScheduleID")]
    [string]$SCCMSQLServer,
    [Parameter(Mandatory=$true,
    ParameterSetName="ByScriptName")]
    [Parameter(Mandatory=$true,
    ParameterSetName="ByScheduleID")]
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
        $SQLCommand = New-Object System.Data.SqlClient.SqlCommand

        $SQLCommand.Connection = $SQLConnection

        $SQLAdapter = New-Object System.Data.SqlClient.SqlDataAdapter

        # No parameters?  Get everything
        if ($PSBoundParameters.Count -eq 0) {
            $SQLCommand.CommandText = "SELECT * FROM dbo.vSMS_ScheduleScripts"
        }
        else {
            # Sanity check. Word characters only until Microsoft gives us an actual professional module
            if ($PSBoundParameters.Values -match "[^a-zA-Z_0-9\-\.]") {
                return "Parameter value may only contain letters, numbers, underscore, hyphen, and periods."     
            }
            $SQLCommand.CommandText = "SELECT * FROM dbo.vSMS_ScheduleScripts WHERE $($PSBoundParameters.Keys) = '$($PSBoundParameters.Values)'"
        }

        $SqlAdapter.SelectCommand = $SQLCommand
        
        $SQLDataset = New-Object System.Data.DataSet

        try {
            $SqlAdapter.fill($SQLDataset) | out-null
        } catch {
            return $error[0]
        }

        if ($SQLDataset.tables.rows) { return $SQLDataset.tables }
        else { return "No matching scheduled script deployments found for $($PSBoundParameters.Keys) `"$($PSBoundParameters.Values)`"" }
    }

    end {
        $SQLConnection.Close()
    }

}

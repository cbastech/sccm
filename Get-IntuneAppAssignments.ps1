<#
    .SYNOPSIS
    Retrieves Intune app assignments based on either application names or target device groups.

    .DESCRIPTION
    This function connects to the Microsoft Graph API and retrieves app assignments for the specified applications or groups.
    It returns a list of custom objects containing the application name, application ID, group name, group ID, filter type, and intent.

    .PARAMETER Group
    An array of group names to search for app assignments.

    .PARAMETER Application
    An array of application names to search for app assignments.

    .EXAMPLE
    Get-IntuneAppAssignments -Application "App1", "App2"
    Get-IntuneAppAssignments -Group "Group1", "Group2"

    .NOTES
    This function requires the Microsoft Graph PowerShell SDK to be installed and configured.
#>

function Get-IntuneAppAssignments {
    [CmdletBinding()]
    param(
    # Array of group names to search for app assignments
    [Parameter(ParameterSetName = 'ByGroup')]
    [string[]]$Group,
    # Array of application names to search for app assignments
    [Parameter(ParameterSetName = 'ByApp')]
    [string[]]$Application
    )

    # Connect to the Microsoft Graph API with the required scopes
    Connect-MGGraph -Scopes "DeviceManagementConfiguration.Read.All, DeviceManagementConfiguration.ReadWrite.All, DeviceManagementApps.Read.All" -NoWelcome

    # Set the consistency level header for the API requests
    $headers = @{ "ConsistencyLevel" = "eventual" }

    # Initialize arrays to store the app IDs, group IDs, and assignments
    $assignments = @()
    $GroupIDs = @()
    $AppIDs = @()



    # Search by Application name

    if ($Application) {
        # Iterate through each application name
        foreach ($AppName in $Application) {

            # Escape the application name for use in the API request
            $EscapedAppName = [uri]::EscapeDataString($AppName)

            # Get the application ID from the Microsoft Graph API
            $app = (Invoke-mgGraphRequest -URI "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/?`$filter=displayName eq '$EscapedAppName'" -Headers $headers).value

            # If the application is found, add its ID to the AppIDs array
            if ($app) {
                $AppIDs += $app
            } else {
                Write-Verbose "Application '$AppName' not found."
            }

            # If no application IDs are found, return $false
            if ($AppIDs.count -eq 0) {
                return $false
            }
        }
        
        # Iterate through each application ID
        foreach ($app in $AppIDs) {

            # Get the group IDs assigned to the application
            $GroupIDs = (Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/v1.0/deviceAppManagement/mobileApps/$($app.id)/assignments" -Method Get).value.target.groupid

            # Iterate through each group ID
            foreach ($GroupID in $GroupIDs) { 

                # Get the assignment details from the Microsoft Graph API
                $assignment = (Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$($app.id)/assignments/").value
                
                # Check if the assignment is for the target group ID
                if ($found = $assignment | where {$_.id -like "$GroupID*"}) {
                    # We found an assignment for our Group ID!
                    # Create a custom object to store the assignment details
                    $result = [PSCustomObject]@{
                        ApplicationName = $app.displayName
                        ApplicationID = $app.id
                        GroupName = (Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/beta/groups/$GroupID/?`$select=displayName").displayName
                        GroupID = $GroupID
                        FilterType = $found.target.deviceAndAppManagementAssignmentFilterType
                        Intent = $found.intent
                    }
                        # Add the assignment details to the assignments array
                        $assignments += $result
                }
            }
        }
    }

    # Search by target device Group
    # NEED TO DO:  What if it's a user group?

    if ($Group) {

        # Write a verbose message to indicate that the process may take a while
        Write-Verbose "This takes a while..."

         # Iterate through each group name
        foreach ($GroupName in $Group) { 

            # Escape the group name for use in the API request
            $EscapedGroupName = [uri]::EscapeDataString($GroupName)

            # Get the group ID from the Microsoft Graph API
            $GroupID = (Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/v1.0/groups/?`$search=`"displayName:$EscapedGroupName`"" -Method Get -Headers $Headers).value.id  # Get the group ID
            
            # If the group is found, add its ID to the GroupIDs array
            if ($GroupID) { 
                $GroupIDs += $GroupID 
            } else {
                Write-Verbose "Group '$GroupName' not found."
            }            
        }

        # If no group IDs are found, return $false
        if ($GroupIDs.count -eq 0) {
            return $false
        }

        # Get all mobile apps from the Microsoft Graph API
        [array]$apps = (Invoke-MgGraphRequest -Uri https://graph.microsoft.com/v1.0/deviceAppManagement/mobileApps -Method GET).value 

        # Iterate through each app
        foreach ($app in $apps) {  

            # Iterate through each group ID
            foreach ($GroupID in $GroupIDs) {  

                # Get the assignment details of the app from the Microsoft Graph API
                $assignment = (Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$($app.id)/assignments/").value
                
                
                # Check if the assignment is for the target group ID 
                if ($found = $assignment | where {$_.id -like "$GroupID*"}) {
                    # We found an assignment for our Group ID!
                    # Create a custom object to store the assignment details
                    $result = [PSCustomObject]@{
                        ApplicationName = $app.displayName
                        ApplicationID = $app.id
                        GroupName = $GroupName
                        GroupID = $GroupID
                        FilterType = $found.target.deviceAndAppManagementAssignmentFilterType
                        Intent = $found.intent
                    }

                        # Add the assignment details to the assignments array
                        $assignments += $result
                }
            }
        }
    }

    # If no assignments are found, return $false
    if (-not $assignments) {
        return $false
    } else { 
        # Return the assignments array
        return $assignments 
    }

}
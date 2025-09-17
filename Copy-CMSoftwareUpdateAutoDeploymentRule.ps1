function Copy-CMSoftwareUpdateAutoDeploymentRule {

<#
        .SYNOPSIS
        Copies the specified ADR (Automatic Deployment Rule) and any existing deployment rules to a new instance.

        .DESCRIPTION
		Uses a combination of existing Configuration Manager commandlets and WMI calls to create a duplicate of an existing ADR (Automatic Deployment Rule) under the name "<ADRName> - Copy", and copies any existing deployment rules. The ADR and deployment rules will be enabled upon creation and set to the same evaluation schedule as the original. This does not copy any associated Software Update Groups.

        .PARAMETER SiteCode
        The three-letter SiteCode of the Configuration Manager site.

        .PARAMETER ADRName
        The name of the ADR to copy.  Alias 'Source'. 

        .INPUTS
        This commandlet does not accept object inputs.

        .OUTPUTS
        Returns $true if successful.

        .EXAMPLE
        PS> Copy-CMSoftwareUpdateAutoDeploymentRule -ADRName "My Chrome ADR" -SiteCode ABC

        .NOTES
		This script must run from the SMS Provider (the server which has the WMI classes necessary).

		This script assumes that the source ADR has at least one of the following rules for 'Software Updates': 'Title' or 'Required', and only explicitly parses those. I have not created a 'kitchen sink' ADR to test the limits of the copying ability.  Theoretically one could parse the entirety of the UpdateRule XML to extract and translate all the properties, but it would require an extensive Property => Parameter mapping, as the properties in the XML do not match the parameters necessary for New-CMSoftwareUpdateAutoDeploymentRule. 

		Example: Parameter 'Required' => XML 'NumMissing'; Parameter 'Title' => XML 'LocalizedDisplayName'
        
    #>

	[cmdletBinding()]
param(
    [Parameter(Mandatory = $True,HelpMessage = "Enter the Site Code for your SCCM Server")]
    [string]$SiteCode,
	[Alias("Source")]
    [Parameter(Mandatory = $True,HelpMessage = "Enter the name of the ADR to copy (Source)")]
    [string]$ADRName
    )
Begin {}
Process {

	try {
		Write-Verbose "Retrieving Auto Deployment Rule: $ADRName"
		$adr = Get-CMSoftwareUpdateAutoDeploymentRule -Name $ADRName

		Write-Verbose "Extracting Deployment Template and Update Rule XML"
		[xml]$ADRTemplateXML = $adr.DeploymentTemplate
		[xml]$ADRUpdateRuleXML = $adr.UpdateRuleXML

		$CollectionID = $ADRTemplateXML.DeploymentCreationActionXML.CollectionId

		$innerXML = $ADRUpdateRuleXML.UpdateXML.UpdateXMLDescriptionItems.InnerXml

		Write-Verbose "Creating initial splat of basic Properties..."
		$splat = @{}

		$splat.Add("Name", "$ADRName - Copy")
		$splat.Add("CollectionID", $CollectionID)

		[regex]$pattern = '<UpdateXMLDescriptionItem PropertyName="(?<PropertyName>.*?)".*?><MatchRules><string>(?<PropertyValue>.*?)</string></MatchRules></UpdateXMLDescriptionItem>'

		Write-Verbose "Extracting Properties from XML"

		$matches = [regex]::Matches($innerXML,$pattern)

		foreach ($match in $matches) {
				switch ($match.Groups['PropertyName'].Value) {
					"NumMissing" { $PropertyName = "Required" }
					"LocalizedDisplayName" { $PropertyName = "Title" }
					default { $PropertyName = $null; }
				}
				
				if ($PropertyName) {
					$splat.Add($PropertyName, [System.Net.WebUtility]::HtmlDecode($match.Groups['PropertyValue'].Value))
				}
			}
		
		Write-Verbose "Creating bare-bones copy of $ADRName as $($splat.Name)"

		try {
			$ADRCopy = New-CMSoftwareUpdateAutoDeploymentRule @splat
		} catch { Write-Error $_.Exception.Message }

		try {
			Write-Verbose "Retrieving WMI Object for $($ADRCopy.Name) from SMS_AutoDeployment namespace."
			[wmi]$ADRCopyWMI = (Get-WmiObject -Class SMS_AutoDeployment -Namespace "root/sms/site_$($SiteCode)" | Where-Object -FilterScript {$_.Name -eq $ADRCopy.Name}).__Path
			
			# Zero out the GUIDs before copying over the Deployment Template block
			Write-Verbose "Zeroing out GUIDS and copying UpdateRule and ContentTemplate XML"
			$NewDeploymentTemplate = $ADR.DeploymentTemplate -replace "<DeploymentId>\{.*\}</DeploymentId>","<DeploymentID/>"
			$NewDeploymentTemplate = $NewDeploymentTemplate -replace "<DeploymentNumber>[0-9]</DeploymentNumber>","<DeploymentNumber/>"
			$ADRCopyWMI.DeploymentTemplate = $NewDeploymentTemplate
			$ADRCopyWMI.UpdateRuleXML = $ADR.UpdateRuleXML
			$ADRCopyWMI.ContentTemplate = $ADR.ContentTemplate
			
			# Make the schedule.  This is stupidly difficult.
			# Credit to https://mulderfiles.nl/2017/12/28/create-a-schedule-token-for-usage-within-sccm/ for
			# the info
			
			$schedule_array = Convert-CMSchedule($adr.Schedule)
			$StdDateTime = Get-Date($schedule_array.StartTime)
			$ConfigMgrDateTime = [System.Management.ManagementDateTimeconverter]::ToDMTFDateTime($StdDateTime)
			
			# However, the 'schedule_array' despite LOOKING like a token, isn't one.  Make a token.
			$class_SMS_ST = [wmiclass]"root/sms/site_${SiteCode}:$($schedule_array.SmsProviderObjectPath)"
			$schedule_token = $class_SMS_ST.CreateInstance()
			
			# Now copy the properties over
			foreach ($property in $schedule_array.PropertyNames) {
				if ($property -eq 'StartTime') {
					$schedule_token.$property = $ConfigMgrDateTime
				} else { 
					$schedule_token.$property = $($schedule_array.PropertyList[$property])
				}
			}
			
			# And convert to ConfigMgr's super duper special string
			$class_SMS_SM = [wmiclass]"root/sms/site_${SiteCode}:SMS_ScheduleMethods"
			$ScheduleString = $class_SMS_SM.WriteToString($schedule_token)
			$ADRCopyWMI.Schedule = $ScheduleString.StringData
			
			
			Write-Verbose "Saving object back to WMI"
			$ADRCopyWMI.Put() | Out-Null
			
			Write-Verbose "Copy of AutoDeploymentRule complete."

		} catch { Write-Error $_.Exception.Message }

		Write-Verbose "Retrieving deployment rules from original ADR..."
		$OriginalDeploymentRules = $ADR | Get-CMAutoDeploymentRuleDeployment

		foreach ($DeploymentRule in $OriginalDeploymentRules) {
			if ($DeploymentRule.CollectionID -eq $CollectionID) { 
				Write-Verbose "Deployment rule for $($DeploymentRule.CollectionName) [$($DeploymentRule.CollectionID)] already present."
				continue # Skip the rule we already created
			} else {
				Write-Verbose "Copying basic Deployment Rule for $($DeploymentRule.CollectionName) [$($DeploymentRule.CollectionID)]"
				$Rule = $ADRCopy | New-CMAutoDeploymentRuleDeployment -CollectionID $DeploymentRule.CollectionID
				
				# We created a blank; now to copy over the previous rule's properties
				
				$NewDeploymentRuleTemplate = $DeploymentRule.DeploymentTemplate -replace "<DeploymentId>\{.*\}</DeploymentId>","" # New deployment rules don't have a Deployment ID at all.
				
				$NewDeploymentRuleTemplate = $NewDeploymentRuleTemplate -replace "<DeploymentNumber>[0-9]</DeploymentNumber>","<DeploymentNumber>$($Rule.DeploymentNumber)</DeploymentNumber>" # Preserve the new deployment number when copying the DeploymentTemplate XML
			
				try {
					Write-Verbose "Retrieving WMI Object for deployment rule from SMS_ADRDeploymentSettings namespace."
					[wmi]$RuleCopyWMI = (Get-WMIObject -Class SMS_ADRDeploymentSettings -Namespace "root/sms/site_$($SiteCode)" | Where-Object -FilterScript {($_.ActionID -eq $Rule.ActionID) -and ($_.CollectionID -eq $Rule.CollectionID) -and ($_.DeploymentNumber -eq $Rule.DeploymentNumber)} )  # Extra checks to make absolutely sure
					
					Write-Verbose "Copying DeploymentTemplate XML"
					$RuleCopyWMI.DeploymentTemplate = $NewDeploymentRuleTemplate
					
					Write-Verbose "Saving object back to WMI"
					$RuleCopyWMI.Put() | Out-Null

					Write-Verbose "Copy of deployment rule for $($DeploymentRule.CollectionName) [$($DeploymentRule.CollectionID)] complete."

				} catch { Write-Error $_.Exception.Message }
					
				
			}
		}

		Write-Verbose "All deployment rules successfully copied."

		return $true

	} catch { Write-Error $_.Exception.Message }

}# End Process Block

} # ENd function
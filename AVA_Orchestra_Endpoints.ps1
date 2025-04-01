<#
.SYNOPSIS
    Crawls data from a URL and outputs process status in a specific format.
.DESCRIPTION
    This script downloads data from a specified URL, processes it, and outputs status
    in the format: [status_code] [scenario_name] [process_name] [process_id] - [status_text]
.PARAMETER Url
    The URL of the data to download and process.
.EXAMPLE
    .\Get-ScenarioData.ps1 -Url "http://customserver/api/data"
    Uses the specified custom URL.
#>

param (
    [Parameter(Mandatory = $false)]
    [string]$Url = "http://srvorc01:8019/api/monitoringData/processFailures"
)

# Set output encoding - use a safer approach
try {
    $OutputEncoding = [System.Text.Encoding]::UTF8
    # Only try to set console encoding if we're in a console host
    if ($Host.Name -eq 'ConsoleHost') {
        [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    }
}
catch {
    Write-Warning "Could not set UTF-8 encoding: $_"
    Write-Warning "Special characters may not display correctly."
}

function Get-ContentFromUrl {
    param (
        [string]$Url
    )
    
    try {
        # Create a WebClient object for downloading the content
        $webClient = New-Object System.Net.WebClient
        $webClient.Encoding = [System.Text.Encoding]::UTF8
        $content = $webClient.DownloadString($Url)
        
        # Save raw content for debugging
        $content | Out-File -FilePath "raw_content.txt" -Encoding utf8
        # Write-Host "Raw content saved to 'raw_content.txt' for inspection" -ForegroundColor Yellow
        
        # Return the raw content
        return $content
    }
    catch {
        Write-Error "Failed to download content from $Url. Error: $_"
        return $null
    }
}

function Convert-ContentToScenarioObject {
    param (
        [string]$Content
    )
    
    try {
        # First, try to determine if the content is JSON
        try {
            $jsonData = $Content | ConvertFrom-Json
            # Write-Host "Content appears to be JSON" -ForegroundColor Green
            
            # Check if the JSON structure matches our expected format
            if ($jsonData.scenario -ne $null) {
                # Write-Host "JSON structure contains 'scenario' property" -ForegroundColor Green
                
                # Process JSON data to filter for newest processes
                foreach ($scenario in $jsonData.scenario) {
                    # Group processes by name and keep only the newest
                    $processGroups = @{}
                    
                    foreach ($process in $scenario.process) {
                        $processName = $process.processName
                        $startTime = [DateTime]::Parse($process.processStartTime)
                        
                        # Add startTimeObj for comparison
                        $process | Add-Member -NotePropertyName 'startTimeObj' -NotePropertyValue $startTime
                        
                        if (-not $processGroups.ContainsKey($processName) -or 
                            $startTime -gt $processGroups[$processName].startTimeObj) {
                            $processGroups[$processName] = $process
                        }
                    }
                    
                    # Replace the processes with only the newest ones
                    $scenario.process = @($processGroups.Values)
                    
                    # Remove the temporary startTimeObj property
                    foreach ($process in $scenario.process) {
                        $process.PSObject.Properties.Remove('startTimeObj')
                    }
                }
                
                return $jsonData
            }
            else {
                Write-Host "JSON structure doesn't match expected format. Attempting to transform..." -ForegroundColor Yellow
                # If needed, transform the JSON to match our expected format
                # This is a placeholder - adjust based on the actual JSON structure
                $transformedData = @{
                    scenario = @()
                }
                
                # Add your transformation logic here
                
                return $transformedData
            }
        }
        catch {
            Write-Host "Content is not valid JSON. Trying XML..." -ForegroundColor Yellow
        }
        
        # If not JSON, try XML
        try {
            $xmlDoc = New-Object System.Xml.XmlDocument
            $xmlDoc.LoadXml($Content)
            Write-Host "Content appears to be XML" -ForegroundColor Green
            
            # Convert XML to our scenario object structure
            $scenarioData = @{
                scenario = @()
            }
            
            # Adjust XPath based on your actual XML structure
            $scenarioNodes = $xmlDoc.SelectNodes("//scenario")
            
            if ($scenarioNodes.Count -eq 0) {
                Write-Warning "No scenario nodes found in the XML. Check the XML structure and adjust the XPath query."
                Write-Host "XML root element: $($xmlDoc.DocumentElement.Name)"
            }
            
            foreach ($scenarioNode in $scenarioNodes) {
                $scenarioObj = @{
                    scenarioName = $scenarioNode.scenarioName
                    process = @()
                }
                
                # Group processes by processName to find the newest for each
                $processGroups = @{}
                
                foreach ($processNode in $scenarioNode.SelectNodes("process")) {
                    $processName = $processNode.processName
                    
                    # Parse the date, handling potential format issues
                    try {
                        $startTime = [DateTime]::Parse($processNode.processStartTime)
                    }
                    catch {
                        # If date parsing fails, use a default old date
                        Write-Warning "Failed to parse date: $($processNode.processStartTime) for process: $processName"
                        $startTime = [DateTime]::MinValue
                    }
                    
                    $processObj = @{
                        processName = $processName
                        processIdentifier = $processNode.processIdentifier
                        processStartTime = $processNode.processStartTime
                        processState = $processNode.processState
                        errorInfo = if ([string]::IsNullOrEmpty($processNode.errorInfo)) { $null } else { $processNode.errorInfo }
                    }
                    
                    if (-not $processGroups.ContainsKey($processName) -or 
                        $startTime -gt $processGroups[$processName].startTime) {
                        $processGroups[$processName] = @{
                            processObj = $processObj
                            startTime = $startTime
                        }
                    }
                }
                
                # Add only the newest process for each process name
                foreach ($group in $processGroups.Values) {
                    $scenarioObj.process += $group.processObj
                }
                
                $scenarioData.scenario += $scenarioObj
            }
            
            return $scenarioData
        }
        catch {
            Write-Host "Content is not valid XML either. Error: $_" -ForegroundColor Red
            
            # Output the first few characters of the content to help diagnose
            if ($Content.Length -gt 0) {
                $previewLength = [Math]::Min(200, $Content.Length)
                Write-Host "Content preview: $($Content.Substring(0, $previewLength))..." -ForegroundColor Yellow
            }
            else {
                Write-Host "Content is empty" -ForegroundColor Red
            }
            
            return $null
        }
    }
    catch {
        Write-Error "Failed to convert content to scenario object. Error: $_"
        return $null
    }
}

function Format-ErrorInfo {
    param (
        [string]$ErrorInfo
    )
    
    if ([string]::IsNullOrEmpty($ErrorInfo)) {
        return "Unknown Error"
    }
    
    # Replace newlines with spaces
    $formattedError = $ErrorInfo -replace '\r?\n', ' '
    
    # Replace square brackets with parentheses
    $formattedError = $formattedError -replace '\[', '(' -replace '\]', ')'
    
    # Trim any excess whitespace
    $formattedError = $formattedError.Trim()
    
    # Limit length if needed (optional)
    if ($formattedError.Length -gt 200) {
        $formattedError = $formattedError.Substring(0, 197) + "..."
    }
    
    return $formattedError
}

function Export-ScenarioDataToJson {
    param (
        [PSCustomObject]$ScenarioData,
        [string]$OutputPath = "scenario_data.json"
    )
    
    try {
        $ScenarioData | ConvertTo-Json -Depth 10 | Out-File -FilePath $OutputPath -Encoding utf8
        Write-Host "Data exported to $OutputPath" -ForegroundColor Yellow
    }
    catch {
        Write-Error "Failed to export data to JSON. Error: $_"
    }
}

# Main execution flow
$content = Get-ContentFromUrl -Url $Url

if ($content) {
    $scenarioData = Convert-ContentToScenarioObject -Content $content
    
    if ($scenarioData) {
        # Output the data directly in the main execution flow
        foreach ($scenario in $scenarioData.scenario) {
            # Use the original scenario name without modification
            $scenarioName = $scenario.scenarioName
            
            foreach ($process in $scenario.process) {
                $processName = $process.processName
                $processId = $process.processIdentifier
                
                # Determine status code and message based on process state
                switch ($process.processState) {
                    "3" {
                        # State 3 = Completed/OK
                        Write-Host 0 "$processName - $scenarioName $processId"
                        # Write-Host 0 "$processName - OK"
                    }
                    { $_ -in "1", "2", "4" } {
                        # States 1, 2, 4 = Warning
                        Write-Host 1 "$processName - $scenarioName $processId"
                        # Write-Host 1 "$processName - Warning"
                    }
                    default {
                        # Unknown state = Critical with error info
                        $errorMessage = Format-ErrorInfo -ErrorInfo $process.errorInfo
                        Write-Host 2 "$processName - $scenarioName $processId - $errorMessage"
                        # Write-Host 2 "$processName - Fehler"
                    }
                }
            }
        }
     
        
    }

}


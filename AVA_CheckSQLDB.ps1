$queryPath = "C:\CheckMKSQL\sql_job_queue.sql"
$outputPath = "C:\CheckMKSQL\QueryResults.txt"

# Execute SQL query
sqlcmd -S srvsqlp01 -d avag_nav_ch_prod -i $queryPath -o $outputPath -W

# Read the file content and skip header rows
$content = Get-Content $outputPath | Select-Object -Skip 2

# Process each line
foreach ($line in $content) {
    # Skip empty lines and the "(rows affected)" line
    if ($line -match '^\s*$' -or $line -match 'rows affected') {
        continue
    }

    # Extract description, status, and start time using regex
    if ($line -match '(.+?)\s+(\d+)\s+(\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}\.\d{3})\s*$') {
        $description = $matches[1].Trim().Replace(' ', '_')
        $status = [int]$matches[2]
        $startTime = [DateTime]::ParseExact($matches[3], "yyyy-MM-dd HH:mm:ss.fff", $null)
        $timeDifference = (Get-Date) - $startTime

        # Output status messages
        if ($status -eq 1 -and $timeDifference.TotalHours -lt -1) {
            Write-Host 2 "$description - Error Job läuft länger als 1 Stunde"
        }
        elseif ($status -in 0,1,4) {
            Write-Host 0 "$description - OK Job ok or In Progress"
        }
        elseif ($status -eq 3) {
            Write-Host 1 "$description - Warning Job on Hold"
        }
        elseif ($status -eq 2) {
            Write-Host 2 "$description - Error in Jobqueue"
        }
    }
}

# Define credentials
$user = "root"
$pass = "root"
$securePass = ConvertTo-SecureString $pass -AsPlainText -Force
$credential = [PSCredential]::new($user, $securePass)

# Function to get miner data
function Get-MinerData($name) {
    $url = "http://10.128.1.218/cgi-bin/miner_$name.cgi"
    $response = Invoke-WebRequest -Uri $url -Credential $credential -AllowUnencryptedAuthentication
    $jsonContent = $response.Content

    if ($jsonContent -like '*Socket connect failed*') {
        return $null
    }

    $data = $jsonContent | ConvertFrom-Json
    return $data
}

# Function to perform a health check on the miner
function Perform-HealthCheck() {
    $data = Get-MinerData -name "summary"
    if ($null -eq $data) {
        return $false
    }

    $miningSpeedString = $data.SUMMARY."GHS 5s"
    $miningSpeed = [decimal]::Parse($miningSpeedString)

    return (($null -ne $miningSpeed) -and ($miningSpeed -gt 0))
}

# Function to get maximum temperature from miner data
function Get-MaxTemperature() {
    $data = Get-MinerData -name "stats"
    if ($null -eq $data) {
        return $null
    }

    $temps = @(
        $data.STATS[1].temp_pcb1,
        $data.STATS[1].temp_pcb2,
        $data.STATS[1].temp_pcb3
    )

    return ($temps | Measure-Object -Maximum).Maximum
}

# Function to show current temperatures
function Show-CurrentTemperatures() {
    $data = Get-MinerData -name "stats"
    if ($null -eq $data) {
        Write-Output "No data available to show temperatures."
        return
    }

    $tempProps = $data.STATS[1].PSObject.Properties |
        Where-Object { $_.Name -like '*temp*' -and $_.Value -match '[1-9]' }

    foreach ($prop in $tempProps) {
        Write-Output ("[{0:u}] {1}={2}" -f (Get-Date), $prop.Name, $prop.Value)
    }
}

# Main monitoring loop
while ($true) {
    $isHealthy = Perform-HealthCheck

    Write-Output ("[{0:u}] Healthy: {1}" -f (Get-Date), $isHealthy)

    if (-not $isHealthy) {
        Show-CurrentTemperatures
        Write-Output ("[{0:u}] Waiting for 3 minutes..." -f (Get-Date))
        Start-Sleep -Seconds 180

        Write-Output ("[{0:u}] Initiating restart" -f (Get-Date))
        Invoke-WebRequest -Uri "http://10.128.1.218/cgi-bin/reboot.cgi" -Credential $credential -AllowUnencryptedAuthentication
        Start-Sleep -Seconds 90

        while ($true) {
            $isHealthy = Perform-HealthCheck
            if ($isHealthy) { break }
            Write-Output ("[{0:u}] Waiting for startup..." -f (Get-Date))
            Start-Sleep -Seconds 10
        }

        Write-Output ("[{0:u}] Reboot complete" -f (Get-Date))
        Show-CurrentTemperatures
    }

    Start-Sleep -Seconds 10
}

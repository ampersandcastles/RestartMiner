$user = "root"
$pass = "root"

$securePass = ConvertTo-SecureString $pass -AsPlainText -Force

$credential = [PSCredential]::new($user, $securePass)

function GetMinerData($name)
{
  $result = Invoke-WebRequest "http://10.128.1.218/cgi-bin/miner_$name.cgi" -Credential $credential

  $buffer = [System.IO.MemoryStream]::new($result.Content)
  $reader = [System.IO.StreamReader]::new($buffer)

  $json = $reader.ReadToEnd()

  if ($json -like '*Socket connect failed*') { return $null }

  $data = $json | ConvertFrom-Json

  return $data
}

function PerformCheck()
{
  $data = GetMinerData("summary")

  if ($data -eq $null) { return $false }

  $currentMiningSpeedString = $data.SUMMARY."GHS 5s"

  $currentMiningSpeed = $currentMiningSpeedString -as [decimal]

  return (($currentMiningSpeed -ne $null) -and ($currentMiningSpeed -gt 0))
}

function CheckTemperatures()
{
  $data = GetMinerData("stats")

  $tempsString = "$($data.STATS[1].temp_pcb1)-$($data.STATS[1].temp_pcb2)-$($data.STATS[1].temp_pcb3)"
  $temps = $tempsString.Split("-")

  return ($temps | Measure -Maximum).Maximum
}

function ShowCurrentTemperatures()
{
  $data = GetMinerData("stats")

  $data.STATS[1].PSObject.Properties | `
    ? { $_ -like '*temp*' -and $_.Value -match "[1-9]" } | `
    % { "[{0:u}] {1}={2}" -f (Get-Date), $_.Name, $_.Value }
}

while ($true)
{
  $isOkay = PerformCheck

  Write-Output ("[{0:u}] Healthy: {1}" -f (Get-Date), $isOkay)

  if (!$isOkay)
  {
    ShowCurrentTemperatures

    Write-Output ("[{0:u}] Waiting for 60 seconds..." -f (Get-Date))

    Start-Sleep -Seconds 60

    Write-Output ("[{0:u}] Initiating restart" -f (Get-Date))

    $result = Invoke-WebRequest "http://10.128.1.218/cgi-bin/reboot.cgi" -Credential $credential

    Start-Sleep -Seconds 90

    while ($true)
    {
      $isOkay = PerformCheck

      if ($isOkay) { break }

      Write-Output ("[{0:u}] Waiting for startup..." -f (Get-Date))

      Start-Sleep -Seconds 10
    }

    Write-Output ("[{0:u}] Reboot complete" -f (Get-Date))

    ShowCurrentTemperatures
  }

  Start-Sleep -Seconds 10
}

$user = "root"
$pass = "root"

$securePass = ConvertTo-SecureString $pass -AsPlainText -Force

$credential = [PSCredential]::new($user, $securePass)

function PerformCheck()
{
  $result = Invoke-WebRequest "http://10.128.1.218/cgi-bin/miner_summary.cgi" -Credential $credential

  $buffer = [System.IO.MemoryStream]::new($result.Content)
  $reader = [System.IO.StreamReader]::new($buffer)

  $json = $reader.ReadToEnd()

  $data = $json | ConvertFrom-Json

  $currentMiningSpeedString = $data.SUMMARY."GHS av"

  $currentMiningSpeed = $currentMiningSpeedString -as [decimal]

  return (($currentMiningSpeed -ne $null) -and ($currentMiningSpeed -gt 0))
}

function CheckTemperatures()
{
  $result = Invoke-WebRequest "http://10.128.1.218/cgi-bin/miner_stats.cgi" -Credential $credential

  $buffer = [System.IO.MemoryStream]::new($result.Content)
  $reader = [System.IO.StreamReader]::new($buffer)

  $json = $reader.ReadToEnd()

  $data = $json | ConvertFrom-Json

  $tempsString = "$($data.STATS[1].temp_pcb1)-$($data.STATS[1].temp_pcb2)-$($data.STATS[1].temp_pcb3)"
  $temps = $tempsString.Split("-")

  return ($temps | Measure -Maximum).Maximum
}

while ($true)
{
  $isOkay = PerformCheck

  Write-Output ("[{0:u}] Healthy: {1}" -f (Get-Date), $isOkay)

  if (!$isOkay)
  {
    while ($true)
    {
      $maxTemp = CheckTemperatures

      Write-Output ("[{0:u}] Current maximum temperature: {1} C" -f (Get-Date), $maxTemp)

      if ($maxTemp -lt 60) { break }

      Start-Sleep -Seconds 60
    }

    Write-Output ("[{0:u}] Initiating restart" -f (Get-Date))

    $result = Invoke-WebRequest "http://10.128.1.218/cgi-bin/reboot.cgi" -Credential $credential

    Start-Sleep -Seconds 30

    while ($true)
    {
      $isOkay = PerformCheck

      if ($isOkay) { break }

      Write-Output ("[{0:u}] Waiting for startup..." -f (Get-Date))

      Start-Sleep -Seconds 60
    }

    Write-Output ("[{0:u}] Reboot complete" -f (Get-Date))
  }

  Start-Sleep -Seconds 10
}

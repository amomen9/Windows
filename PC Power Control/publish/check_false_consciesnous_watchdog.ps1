$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$exePath = Join-Path $PSScriptRoot 'PCPowerControl.exe'
$restartDelaySeconds = 5

while ($true) {
    if (-not (Test-Path -LiteralPath $exePath)) {
        Write-Host ("{0}: Waiting for executable to appear at {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $exePath)
        Start-Sleep -Seconds $restartDelaySeconds
        continue
    }

    try {
        Write-Host ("{0}: Starting {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $exePath)
        $process = Start-Process -FilePath $exePath -WorkingDirectory $PSScriptRoot -PassThru -WindowStyle Hidden
        Wait-Process -Id $process.Id
        Write-Host ("{0}: {1} exited; restarting in {2}s" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $exePath, $restartDelaySeconds)
    }
    catch {
        Write-Host ("{0}: Watchdog error: {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $_.Exception.Message)
    }

    Start-Sleep -Seconds $restartDelaySeconds
}

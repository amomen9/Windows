#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Builds the PC Power Control app and creates or recreates the scheduled task.
.DESCRIPTION
    This setup script publishes the compiled runtime executable and registers a
    scheduled task that starts a watchdog script at boot. The watchdog keeps the
    executable running by relaunching it whenever it exits.
.EXAMPLE
    .\check_false_consciesnous_setup.ps1
#>

param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Clear-Host

$taskName = 'CheckFalseConsciousness'
$scriptRoot = $PSScriptRoot
$projectFile = Join-Path $scriptRoot 'PCPowerControl.csproj'
$publishDir = Join-Path $scriptRoot 'publish'
$publishExe = Join-Path $publishDir 'PCPowerControl.exe'
$watchdogScript = Join-Path $publishDir 'check_false_consciesnous_watchdog.ps1'

if (-not (Test-Path -LiteralPath $projectFile)) {
    throw "Project file not found: $projectFile"
}

Write-Host "Publishing $projectFile to $publishDir ..."
& dotnet publish $projectFile -c Release -o $publishDir | Out-Host

if (-not (Test-Path -LiteralPath $publishExe)) {
    throw "Published executable not found: $publishExe"
}

$watchdogContent = @"
`$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

`$exePath = Join-Path `$PSScriptRoot 'PCPowerControl.exe'
`$restartDelaySeconds = 5

while (`$true) {
    if (-not (Test-Path -LiteralPath `$exePath)) {
        Write-Host ("{0}: Waiting for executable to appear at {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), `$exePath)
        Start-Sleep -Seconds `$restartDelaySeconds
        continue
    }

    try {
        Write-Host ("{0}: Starting {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), `$exePath)
        `$process = Start-Process -FilePath `$exePath -WorkingDirectory `$PSScriptRoot -PassThru -WindowStyle Hidden
        Wait-Process -Id `$process.Id
        Write-Host ("{0}: {1} exited; restarting in {2}s" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), `$exePath, `$restartDelaySeconds)
    }
    catch {
        Write-Host ("{0}: Watchdog error: {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), `$_.Exception.Message)
    }

    Start-Sleep -Seconds `$restartDelaySeconds
}
"@

Set-Content -LiteralPath $watchdogScript -Value $watchdogContent -Encoding UTF8

$watchdogArguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $watchdogScript + '"'

$taskXml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Description>Hibernates the laptop when on battery power with the lid closed and keeps the executable running.</Description>
    <URI>\$taskName</URI>
  </RegistrationInfo>
  <Triggers>
    <BootTrigger>
      <Enabled>true</Enabled>
      <Delay>PT30S</Delay>
    </BootTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <UserId>S-1-5-18</UserId>
      <RunLevel>HighestAvailable</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <AllowHardTerminate>true</AllowHardTerminate>
    <StartWhenAvailable>true</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
    <IdleSettings>
      <StopOnIdleEnd>false</StopOnIdleEnd>
      <RestartOnIdle>false</RestartOnIdle>
    </IdleSettings>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <Enabled>true</Enabled>
    <Hidden>false</Hidden>
    <RunOnlyIfIdle>false</RunOnlyIfIdle>
    <DisallowStartOnRemoteAppSession>false</DisallowStartOnRemoteAppSession>
    <UseUnifiedSchedulingEngine>true</UseUnifiedSchedulingEngine>
    <WakeToRun>false</WakeToRun>
    <ExecutionTimeLimit>PT0S</ExecutionTimeLimit>
    <RestartOnFailure>
      <Interval>PT1M</Interval>
      <Count>999</Count>
    </RestartOnFailure>
    <Priority>6</Priority>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>powershell.exe</Command>
      <Arguments>$watchdogArguments</Arguments>
      <WorkingDirectory>$publishDir</WorkingDirectory>
    </Exec>
  </Actions>
</Task>
"@

$existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($existing) {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    Write-Host "Existing task '$taskName' removed."
}

$tmpXml = [System.IO.Path]::ChangeExtension([System.IO.Path]::GetTempFileName(), '.xml')
[System.IO.File]::WriteAllText($tmpXml, $taskXml, [System.Text.Encoding]::Unicode)

try {
    $out = schtasks.exe /Create /TN $taskName /XML $tmpXml /F
    Write-Host $out
}
finally {
    Remove-Item $tmpXml -Force -ErrorAction SilentlyContinue
}

& wevtutil.exe sl Microsoft-Windows-TaskScheduler/Operational /e:true | Out-Null

Write-Host "Task '$taskName' registered - starts at boot as NT AUTHORITY\SYSTEM."
Write-Host "Watchdog script: $watchdogScript"
Write-Host "Task Scheduler history enabled: Microsoft-Windows-TaskScheduler/Operational"
Write-Host "Published executable: $publishExe"
Write-Host "Publish directory: $publishDir"

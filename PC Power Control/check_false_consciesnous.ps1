#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Monitors battery/lid state and hibernates the laptop when on battery with the lid closed.
    Run with -Setup once (as administrator) to register the scheduled task.
.EXAMPLE
    .\check_false_consciesnous.ps1 -Setup
#>

param([switch]$Setup)
Clear-Host
$Setup = $true

# ---------- SETUP: REGISTER THE SCHEDULED TASK ------------------------------
if ($Setup) {
    $scriptPath    = $MyInvocation.MyCommand.Path
    $taskName      = 'CheckFalseConsciousness'
    $t0             = (Get-Date).AddSeconds(30)
    $startBoundary  = $t0.ToString('yyyy-MM-ddTHH:mm:ss')
    $startBoundary20 = $t0.AddSeconds(20).ToString('yyyy-MM-ddTHH:mm:ss')
    $startBoundary40 = $t0.AddSeconds(40).ToString('yyyy-MM-ddTHH:mm:ss')

    $taskXml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Description>Puts the laptop to sleep when on battery power with the lid closed.</Description>
    <URI>\$taskName</URI>
  </RegistrationInfo>
  <Triggers>
    <TimeTrigger>
      <Repetition>
        <Interval>PT1M</Interval>
        <StopAtDurationEnd>false</StopAtDurationEnd>
      </Repetition>
      <StartBoundary>$startBoundary</StartBoundary>
      <Enabled>true</Enabled>
    </TimeTrigger>
    <TimeTrigger>
      <Repetition>
        <Interval>PT1M</Interval>
        <StopAtDurationEnd>false</StopAtDurationEnd>
      </Repetition>
      <StartBoundary>$startBoundary20</StartBoundary>
      <Enabled>true</Enabled>
    </TimeTrigger>
    <TimeTrigger>
      <Repetition>
        <Interval>PT1M</Interval>
        <StopAtDurationEnd>false</StopAtDurationEnd>
      </Repetition>
      <StartBoundary>$startBoundary40</StartBoundary>
      <Enabled>true</Enabled>
    </TimeTrigger>
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
    <ExecutionTimeLimit>PT1M</ExecutionTimeLimit>
    <Priority>6</Priority>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>powershell.exe</Command>
      <Arguments>-NonInteractive -NoProfile -ExecutionPolicy Bypass -File "$scriptPath"</Arguments>
    </Exec>
  </Actions>
</Task>
"@

    # Drop the existing task first if it exists, then recreate it cleanly.
    $existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($existing) {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
        Write-Host "Existing task '$taskName' removed."
    }

    # Register-ScheduledTask -Xml rejects sub-minute intervals (PT20S).
    # schtasks.exe /Create /XML passes the XML directly to the engine without that check.
    $tmpXml = [System.IO.Path]::ChangeExtension([System.IO.Path]::GetTempFileName(), '.xml')
    [System.IO.File]::WriteAllText($tmpXml, $taskXml, [System.Text.Encoding]::Unicode)
    try {
        $out = schtasks.exe /Create /TN $taskName /XML $tmpXml /F
        Write-Host $out
    } finally {
        Remove-Item $tmpXml -Force -ErrorAction SilentlyContinue
    }

    Write-Host "Task '$taskName' registered - runs every 20 s as NT AUTHORITY\SYSTEM."
    Write-Host "Log file: $(Join-Path (Split-Path $scriptPath) 'check_false_consciesnous.log')"
    exit 0
}

# ---------- P/INVOKE: GetSystemPowerStatus ----------------------------------
if (-not ('PowerApi' -as [type])) {
    Add-Type @'
using System;
using System.Runtime.InteropServices;

[StructLayout(LayoutKind.Sequential)]
public struct SystemPowerStatus {
    public byte ACLineStatus;      // 0 = battery, 1 = AC, 255 = unknown
    public byte BatteryFlag;
    public byte BatteryLifePercent;
    public byte SystemStatusFlag;
    public uint BatteryLifeTime;
    public uint BatteryFullLifeTime;
}

public static class PowerApi {
    [DllImport("Kernel32.dll")]
    public static extern bool GetSystemPowerStatus(out SystemPowerStatus sps);
}
'@
}

# ---------- FUNCTIONS -------------------------------------------------------

function Get-IsOnBattery {
    $s = New-Object SystemPowerStatus
    [PowerApi]::GetSystemPowerStatus([ref]$s) | Out-Null
    return ($s.ACLineStatus -eq 0)
}

function Get-IsLidClosed {
    # Returns: $true = closed | $false = open | $null = indeterminate (fail-safe -> treat as open)
    #
    # Rule: if ANY monitor reports Active = true, at least one display is on -> lid is open
    #       (or an external display is connected in clamshell mode, in which case we also
    #       should not sleep). Only zero active monitors means lid closed with no external display.
    try {
        $monitors = @(Get-WmiObject -Namespace 'root\wmi' `
                      -Class 'WmiMonitorBasicDisplayParams' -ErrorAction Stop)
        if ($monitors.Count -eq 0) { return $null }

        $activeCount = ($monitors | Where-Object { $_.Active -eq $true }).Count
        return ($activeCount -eq 0)
    } catch {
        return $null
    }
}

function Get-Temperatures {
    $deg = [char]176   # degree symbol - defined here to stay encoding-agnostic
    $cpu = 'N/A'; $gpu = 'N/A'; $mb = 'N/A'

    # -- ACPI thermal zones (readable by SYSTEM, no agent needed) ------------
    # Temperature values are in tenths of Kelvin; convert to Celsius.
    try {
        $zones = @(Get-WmiObject -Namespace 'root\wmi' `
                   -Class 'MSAcpi_ThermalZoneTemperature' -ErrorAction Stop)

        $named = @{}
        foreach ($zone in $zones) {
            $c    = [math]::Round(($zone.CurrentTemperature - 2732) / 10, 1)
            $name = $zone.InstanceName.ToUpper()
            if    ($name -match 'CPU|PROC|CORE') { $named['cpu'] = $c }
            elseif ($name -match 'GPU|VGA|DGPU') { $named['gpu'] = $c }
            elseif ($name -match 'MB|SYS|BOARD') { $named['mb']  = $c }
            else                                  { $named["zone_$($zone.InstanceName)"] = $c }
        }

        if ($named.ContainsKey('cpu')) { $cpu = "$($named['cpu'])${deg}C" }
        if ($named.ContainsKey('gpu')) { $gpu = "$($named['gpu'])${deg}C" }
        if ($named.ContainsKey('mb'))  { $mb  = "$($named['mb'])${deg}C"  }

        # Fallback: assign by descending temperature if names did not match
        if ($cpu -eq 'N/A' -and $zones.Count -ge 1) {
            $sorted = $zones |
                      ForEach-Object { [math]::Round(($_.CurrentTemperature - 2732) / 10, 1) } |
                      Sort-Object -Descending
            $cpu = "$($sorted[0])${deg}C"
            if ($sorted.Count -ge 2) { $mb = "$($sorted[1])${deg}C" }
        }
    } catch {}

    # -- GPU: nvidia-smi (fastest, works headless) ---------------------------
    if ($gpu -eq 'N/A') {
        try {
            $nv = & nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits 2>$null
            if ($LASTEXITCODE -eq 0 -and $nv) { $gpu = "$($nv.Trim())${deg}C" }
        } catch {}
    }

    # -- GPU: LibreHardwareMonitor / OpenHardwareMonitor WMI fallback --------
    if ($gpu -eq 'N/A') {
        foreach ($ns in @('root\LibreHardwareMonitor', 'root\OpenHardwareMonitor')) {
            try {
                $s = Get-WmiObject -Namespace $ns -Class Sensor `
                     -Filter "SensorType='Temperature' AND Name='GPU Core'" -ErrorAction Stop
                if ($s) { $gpu = "$([math]::Round($s.Value, 1))${deg}C"; break }
            } catch {}
        }
    }

    return "CPU: $cpu | GPU: $gpu | MB: $mb"
}

# ---------- MAIN ------------------------------------------------------------

$ts        = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$onBattery = Get-IsOnBattery
$lidClosed = Get-IsLidClosed   # $null = indeterminate
$tempStr   = Get-Temperatures

# Fail-safe: unknown lid state is treated as open (never sleep unintentionally).
$lidIsOpen = ($lidClosed -ne $true)

    $msg = if    (-not $onBattery -and $lidIsOpen)      { "${ts}: Abort ... - The PC is running on AC power, and the lid is open. [$tempStr]" }
       elseif ($onBattery     -and $lidIsOpen)       { "${ts}: Abort ... - The PC is running on battery power, but the lid is open. [$tempStr]" }
       elseif (-not $onBattery -and -not $lidIsOpen) { "${ts}: Abort ... - The PC is running on AC power, and the lid is closed. [$tempStr]" }
       else                                          { "${ts}: Hibernating ... - The PC is running on battery power, and the lid is closed. [$tempStr]" }

Write-Output $msg

$logFile = Join-Path $PSScriptRoot 'check_false_consciesnous.log'
Add-Content -Path $logFile -Value $msg -Encoding UTF8

# Trigger hibernation only when running on battery with the lid confirmed closed.
if ($onBattery -and -not $lidIsOpen) {
    Start-Sleep -Seconds 1
    & shutdown.exe /h
}

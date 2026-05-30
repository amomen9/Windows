# PC Power Control

Automatically puts a Windows laptop into hibernation when it is running on battery power **and** the lid is closed. A scheduled task fires every 20 seconds as `NT AUTHORITY\SYSTEM` — no user session required.

---

## Files

| File | Purpose |
|------|---------|
| `check_false_consciesnous.ps1` | Main script — contains both the scheduled-task registration logic (`-Setup`) and the per-execution monitoring logic |
| `check_false_consciesnous.log` | Append-only log file created on first run, one line per execution |

---

## Requirements

- Windows 10 / 11 (x64)
- PowerShell 5.1 or later
- Must be run as **Administrator** for setup
- Optional: [LibreHardwareMonitor](https://github.com/LibreHardwareMonitor/LibreHardwareMonitor) or [OpenHardwareMonitor](https://openhardwaremonitor.org/) running with its WMI service enabled for more accurate GPU temperatures
- Optional: NVIDIA GPU with drivers installed for `nvidia-smi` GPU temperature readings

---

## Setup

Open PowerShell **as Administrator** and run:

```powershell
.\check_false_consciesnous.ps1 -Setup
```

This registers a scheduled task named `CheckFalseConsciousness` that runs the script every 20 seconds indefinitely as `NT AUTHORITY\SYSTEM` with the highest available privileges. The task starts 30 seconds after registration and resumes automatically after sleep, hibernate, or reboot.

To verify the task was created:

```powershell
Get-ScheduledTask -TaskName 'CheckFalseConsciousness'
```

To remove the task later:

```powershell
Unregister-ScheduledTask -TaskName 'CheckFalseConsciousness' -Confirm:$false
```

---

## Behavior

At every 20-second interval the script evaluates two conditions — **power source** and **lid state** — and prints (and logs) exactly one of these messages:

```
<timestamp>: Abort ... - The PC is running on AC power, and the lid is open. [CPU: 61°C | GPU: 54°C | MB: 48°C]
<timestamp>: Abort ... - The PC is running on battery power, but the lid is open. [CPU: 61°C | GPU: 54°C | MB: 48°C]
<timestamp>: Abort ... - The PC is running on AC power, and the lid is closed. [CPU: 61°C | GPU: 54°C | MB: 48°C]
<timestamp>: Hibernating ... - The PC is running on battery power, and the lid is closed. [CPU: 61°C | GPU: 54°C | MB: 48°C]
```

Only the last case triggers hibernation. The machine wakes normally from any configured wake source (power button, keyboard, scheduled wake timer, etc.).

---

## How it works

### Power source detection

Uses the Win32 `GetSystemPowerStatus` API (Kernel32.dll) via P/Invoke. The `ACLineStatus` field returns `0` for battery and `1` for AC. This is the same data source Windows uses internally and is reliable in all power states.

### Lid state detection

Queries `WmiMonitorBasicDisplayParams.Active` in the `root\wmi` WMI namespace. The built-in laptop panel (identified as the lexicographically first monitor instance) transitions to `Active = false` when the lid is physically closed.

**Fail-safe:** if the WMI query fails or returns no data (e.g., no display driver loaded), the lid state is treated as **open** and sleep is never triggered unintentionally.

**Clamshell mode:** if an external monitor is connected while the lid is closed, the external display stays active. The script correctly detects the built-in panel as inactive and treats the lid as closed. Whether to sleep in that scenario is controlled solely by the battery condition — on AC power the machine will not sleep even with the lid closed.

### Temperature reporting

Temperatures are collected from three sources and reported on every execution regardless of the sleep decision:

| Sensor | Source | Notes |
|--------|--------|-------|
| CPU | `MSAcpi_ThermalZoneTemperature` (`root\wmi`) | ACPI thermal zones; works headless as SYSTEM with no third-party agent. Zone names are matched by keyword (`CPU`, `PROC`, `CORE`); falls back to the hottest zone. |
| GPU | `nvidia-smi` → LibreHardwareMonitor WMI → OpenHardwareMonitor WMI | Tried in order; reports `N/A` if none are available. |
| MB (motherboard) | `MSAcpi_ThermalZoneTemperature` (`root\wmi`) | Matched by keyword (`MB`, `SYS`, `BOARD`); falls back to the second-hottest zone. |

### Hibernation command

```
shutdown.exe /h
```

This invokes Windows hibernation directly.

### Scheduled task internals

The task is registered via a raw XML definition so that a **20-second repetition interval** can be set — the Task Scheduler GUI enforces a 1-minute minimum, but the underlying XML schema supports seconds. Key settings:

| Setting | Value | Reason |
|---------|-------|--------|
| `RunLevel` | `HighestAvailable` | Full administrative privileges |
| `UserId` | `S-1-5-18` (SYSTEM) | Runs without any user logged in |
| `MultipleInstancesPolicy` | `IgnoreNew` | Prevents overlap if a run takes longer than 20 s |
| `DisallowStartIfOnBatteries` | `false` | Must run on battery to be useful |
| `StopIfGoingOnBatteries` | `false` | Same reason |
| `StartWhenAvailable` | `true` | Catches up missed triggers after wake/reboot |
| `ExecutionTimeLimit` | `PT1M` | Hard-kills a hung instance after 1 minute |

---

## Log file

Each execution appends one UTF-8 line to `check_false_consciesnous.log` in the same directory as the script. To tail the log in real time:

```powershell
Get-Content .\check_false_consciesnous.log -Wait -Tail 20
```

---

## Troubleshooting

**Lid state always shows as open**
The `WmiMonitorBasicDisplayParams` class requires the display driver stack to be loaded. On some systems this class is unavailable when no user is logged in. In that case the script logs `Abort` (fail-safe) and never hibernates. As a workaround, configure the native Windows lid-close action to sleep via Settings → System → Power & sleep → Additional power settings → Choose what closing the lid does, and disable this script.

**Temperatures show N/A for GPU**
Install [LibreHardwareMonitor](https://github.com/LibreHardwareMonitor/LibreHardwareMonitor), enable *Run On Windows Startup* and *Options → WMI Provider*, then restart the scheduled task. NVIDIA users can alternatively rely on `nvidia-smi` which ships with the driver.

**Script does not run / access denied**
Confirm the task is registered and enabled:
```powershell
Get-ScheduledTask -TaskName 'CheckFalseConsciousness' | Select-Object State, LastRunTime, LastTaskResult
```
A `LastTaskResult` of `0x1` means the script exited with an error. Check the log file for the last written line to see where execution stopped.

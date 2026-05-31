# PC Power Control

## Intro

Ever closed your laptop, put it in a bag or backpack, and later noticed that it had woken up and become dangerously hot inside the bag? That can cause real problems:

1. The device can be damaged or wear out faster. In bad cases, fans can fail, start making noise, or stop working properly.
2. The battery can be drained when you needed it later.
3. Energy is wasted.
4. There is a small but real chance of heat damage to the bag and nearby items.

This project is meant to prevent that situation. It automatically hibernates a Windows laptop when it is on battery power and the lid is closed, so if the machine wakes at the wrong time or you forgot to shut it down properly, it can protect itself before heat builds up. The core power-state logic lives in a single compiled Windows app so the decision stays together and runs reliably.

---

## Files

| File | Purpose |
|------|---------|
| `Program.cs` | Compiled runtime app: listens for lid/power notifications, reads temperatures, logs decisions, and hibernates when appropriate |
| `PCPowerControl.csproj` | Windows desktop project used to build the runtime app |
| `check_false_consciesnous_setup.ps1` | Setup script: publishes the app and registers the scheduled task |
| `check_false_consciesnous.ps1` | Legacy PowerShell runtime script kept for reference |

---

## Requirements

- Windows 10 / 11 (x64)
- .NET 10 SDK installed
- Administrator rights to register the scheduled task
- PowerShell 5.1 or later for running the setup script
- Optional: NVIDIA drivers and `nvidia-smi` for GPU temperature reporting
- Optional: LibreHardwareMonitor or OpenHardwareMonitor if you want additional WMI temperature sources

---

## Setup

Open PowerShell **as Administrator** in this folder and run:

```powershell
.\check_false_consciesnous_setup.ps1
```

This script:

- Publishes the compiled app into `.\publish\`
- Creates a watchdog script beside the executable
- Registers or replaces the `CheckFalseConsciousness` scheduled task
- Configures the task to run at boot as `NT AUTHORITY\SYSTEM`
- Points the task at the watchdog so the executable is relaunched if it exits
- Enables Task Scheduler history logging

To verify the task was created:

```powershell
Get-ScheduledTask -TaskName 'CheckFalseConsciousness'
```

To remove the task later:

```powershell
Unregister-ScheduledTask -TaskName 'CheckFalseConsciousness' -Confirm:$false
```

---

## Runtime behavior

The executable watches for Windows power notifications and logs one of these messages whenever the power source or lid state changes:

```text
<timestamp>: Abort ... - The PC is running on AC power, and the lid is open. [CPU: 61°C | GPU: 54°C | MB: 48°C]
<timestamp>: Abort ... - The PC is running on battery power, but the lid is open. [CPU: 61°C | GPU: 54°C | MB: 48°C]
<timestamp>: Abort ... - The PC is running on AC power, and the lid is closed. [CPU: 61°C | GPU: 54°C | MB: 48°C]
<timestamp>: Hibernating ... - The PC is running on battery power, and the lid is closed. [CPU: 61°C | GPU: 54°C | MB: 48°C]
```

Only the final case triggers hibernation.

### Temperature reporting

Temperatures are collected on every execution from these sources:

| Sensor | Source |
|--------|--------|
| CPU | `MSAcpi_ThermalZoneTemperature` via Windows WMI |
| GPU | `nvidia-smi`, then fallback WMI sources if available |
| MB | `MSAcpi_ThermalZoneTemperature` via Windows WMI |

If a source is unavailable, that field is logged as `N/A`.

---

## Waking up reasons

A laptop can wake for many reasons, not just the lid opening. Common causes include:

- USB devices such as mice, keyboards, dongles, receivers, docks, and external adapters
- Bluetooth devices that are allowed to wake the machine
- Network adapters using Wake-on-LAN
- Wake timers created by scheduled tasks, maintenance, or update activity
- Power-button, lid, AC-attach, or firmware-triggered wake events
- BIOS/UEFI options such as RTC alarms or platform wake features

If the laptop is going into a bag, the safest decision is usually to prefer hibernation and to reduce or remove wake sources that you do not actually need.

### Useful `powercfg` commands

Windows exposes wake information through `powercfg`:

```powershell
powercfg /lastwake
```

Shows the most recent wake source. This is the first command to check when you are trying to identify what woke the laptop.

```powershell
powercfg /devicequery wake_armed
```

Lists devices that are currently allowed to wake the system. This often reveals USB mice, keyboards, docks, or adapters that can wake the laptop even when you did not expect them to.

```powershell
powercfg /waketimers
```

Shows wake timers that can bring the laptop out of sleep for scheduled work.

```powershell
powercfg /devicequery wake_programmable
```

Lists devices that can be armed for wake. This helps when deciding whether a device should stay wake-capable or be disabled.

### How to tweak wake behavior

If a device should not wake the laptop, disable its wake permission. You can do that in Device Manager or with `powercfg`:

```powershell
powercfg /devicedisablewake "Device Name"
```

To allow it again later:

```powershell
powercfg /deviceenablewake "Device Name"
```

Typical candidates to review:

- USB mouse receivers
- USB keyboards
- Bluetooth adapters
- Docking stations
- Network adapters with Wake-on-LAN enabled

### Practical countermeasures

When the machine is used mostly on the go:

- Prefer hibernate over sleep before putting the laptop in a bag
- Remove wake permission from devices you do not need to wake the system
- Disable Wake-on-LAN if remote wake is not required
- Review scheduled tasks that create wake timers
- Check BIOS/UEFI wake settings if Windows changes do not solve the issue
- Re-test with `powercfg /lastwake` after an unexpected wake to confirm the source

A good rule is to keep only the minimum wake sources necessary for your workflow. If remote wake or a dock matters, keep those enabled; otherwise, strip wake permission aggressively when portability and heat safety matter more.

---

## How it works

- `GetSystemPowerStatus` is used to detect whether the laptop is on AC power or battery power.
- Windows power-setting notifications are used to detect lid and power-source changes.
- The app runs as a background Windows Forms process with a hidden window so it can receive those notifications reliably.
- The scheduled task launches a watchdog script, and the watchdog restarts the executable whenever it exits.
- When the laptop is on battery and the lid is closed, the app waits briefly and then runs:

```powershell
shutdown.exe /h
```

---

## Build manually

If you want to build the executable yourself:

```powershell
dotnet build .\PCPowerControl.csproj -c Release
```

To publish the runnable executable:

```powershell
dotnet publish .\PCPowerControl.csproj -c Release -o .\publish
```

### Command-line options

By default, the executable refreshes every `20000` milliseconds and sleeps the laptop when it needs to suspend.

You can change how often the executable refreshes its battery state with either:

```powershell
.\publish\PCPowerControl.exe --interval-ms 5000
```

or:

```powershell
.\publish\PCPowerControl.exe -i 5000
```

You can also choose the suspend action:

```powershell
.\publish\PCPowerControl.exe --action sleep
```

or:

```powershell
.\publish\PCPowerControl.exe --action hibernate
```

Short form:

```powershell
.\publish\PCPowerControl.exe -a sleep
```

The interval value is clamped between `250` and `60000` milliseconds.

---

## Notes

- The legacy PowerShell runtime is still present in the repo, but the scheduled task now uses the compiled executable through the watchdog wrapper.
- Logs are written beside the published executable.

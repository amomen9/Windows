# Windows Machines Group Update

Run Windows Updates on multiple remote Windows machines over **SSH**, starting the update operation **in the background** on each target and immediately moving on to the next target.

This folder provides:

- `fn-RemoteWindowsUpdate.ps1`: A single self-contained script that includes:
  - the orchestrator function `fn-RemoteWindowsUpdate` (runs locally)
  - an embedded remote payload script (sent to and executed on each remote host)

## Prerequisites

On the machine you run the orchestrator from:

- OpenSSH client available (`ssh`).

On each remote Windows machine:

- OpenSSH Server installed and running.
- PowerShell available (`powershell.exe`).
- `PSWindowsUpdate` module installed.

## What it does

For each entry in `-RemoteComputers` (DNS name or IP):

1. Sends an embedded payload script over SSH.
2. Writes it to `$env:ProgramData\WindowsMachinesGroupUpdate\u1-remote-windows-update.ps1` on the remote.
3. Executes it.
4. The payload immediately starts a **detached background PowerShell process** that runs:

`Get-WindowsUpdate -AcceptAll -Install`

…and conditionally includes `-AutoReboot`, `-ScheduleJob`, and `-ScheduleReboot` if you provided them.

## Usage

Dot-source the function, then call it:

```powershell
. "$PSScriptRoot\fn-RemoteWindowsUpdate.ps1"

fn-RemoteWindowsUpdate \
  -RemoteComputers @('server1.contoso.com','10.10.10.25')
```

With SSH username and identity file:

```powershell
. "$PSScriptRoot\fn-RemoteWindowsUpdate.ps1"

fn-RemoteWindowsUpdate \
  -RemoteComputers @('server1','server2') \
  -SshUser 'Administrator' \
  -IdentityFile "$HOME\.ssh\id_ed25519"
```

With optional parameters:

```powershell
. "$PSScriptRoot\fn-RemoteWindowsUpdate.ps1"

fn-RemoteWindowsUpdate \
  -RemoteComputers @('server1','server2') \
  -AutoReboot \
  -ScheduleJob ([datetime]::new(2025,12,30,23,0,0)) \
  -ScheduleReboot ([datetime]::new(2025,12,31,2,0,0))
```

Run custom scripts before/after starting the update worker on each target:

```powershell
. "$PSScriptRoot\fn-RemoteWindowsUpdate.ps1"

fn-RemoteWindowsUpdate \
  -RemoteComputers @('server1','server2') \
  -SshUser 'Administrator' \
  -IdentityFile "$HOME\.ssh\id_ed25519" \
  -ScriptToRunBefore {
    Write-Output "Before: $(hostname)"
    whoami
  } \
  -ScriptToRunAfter {
    Write-Output "After: update worker was started"
  }
```

Note: `-ScriptToRunAfter` runs after the update worker is started (it does not wait for updates to complete).

## Logs

Each target writes logs locally on the target under:

- `$env:ProgramData\PSWindowsUpdate\RemoteWU-YYYYMMDD-HHMMSS.log`

## Notes

- `-AcceptAll -Install` are always included.
- The orchestrator uses `ssh -o BatchMode=yes` so it won’t hang prompting for passwords.
  If you pass `-IdentityFile`, it also uses `-i <key> -o IdentitiesOnly=yes`.

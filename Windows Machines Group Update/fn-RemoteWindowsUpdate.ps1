<#
This script is intentionally self-contained.

It includes:
- Local orchestrator function: fn-RemoteWindowsUpdate (runs on your admin workstation)
- Embedded remote payload: a small script written to each target and launched in the background

The remote payload always runs:
  Get-WindowsUpdate -AcceptAll -Install
and optionally includes -AutoReboot/-ScheduleJob/-ScheduleReboot when you pass those to fn-RemoteWindowsUpdate.
#>

function fn-RemoteWindowsUpdate {
	[CmdletBinding()]
	param(
		# When set, passes -AutoReboot to Get-WindowsUpdate on the remote host.
		[Parameter()]
		[switch]$AutoReboot,

		# If provided, passed through to Get-WindowsUpdate -ScheduleJob on the remote host.
		[Parameter()]
		[datetime]$ScheduleJob,

		# If provided, passed through to Get-WindowsUpdate -ScheduleReboot on the remote host.
		[Parameter()]
		[datetime]$ScheduleReboot,

		# Optional SSH username. If provided, targets are used as user@host.
		[Parameter()]
		[string]$SshUser,

		# Optional private key to use for SSH authentication.
		[Parameter()]
		[string]$IdentityFile,

		# Optional script run on the remote host BEFORE starting the update worker.
		# Can be a ScriptBlock or a string.
		[Parameter()]
		[object]$ScriptToRunBefore,

		# Optional script run on the remote host AFTER the update worker is started.
		# Note: this does NOT wait for updates to complete.
		# Can be a ScriptBlock or a string.
		[Parameter()]
		[object]$ScriptToRunAfter,

		# Required list of targets. Each entry can be a DNS name or IP.
		[Parameter(Mandatory)]
		[string[]]$RemoteComputers
	)

	# ---------------------------------------------------------------------
	# Embedded remote payload (u1): written to each target and executed.
	# The u1 payload immediately spawns a hidden background worker process
	# that runs Get-WindowsUpdate and writes logs to ProgramData.
	# ---------------------------------------------------------------------
	$u1Text = @'
[CmdletBinding()]
param(
	# When true, includes -AutoReboot in Get-WindowsUpdate.
	[Parameter()]
	[bool]$AutoReboot = $false,

	# Optional schedule values (passed from orchestrator).
	[Parameter()]
	[datetime]$ScheduleJob,

	[Parameter()]
	[datetime]$ScheduleReboot,

	# Internal switch: when set, this instance becomes the background worker.
	[Parameter()]
	[switch]$Worker,

	# Worker-mode: schedule values as ISO 8601 round-trip strings.
	[Parameter()]
	[string]$ScheduleJobIso,

	[Parameter()]
	[string]$ScheduleRebootIso,

	# Worker-mode: log file path.
	[Parameter()]
	[string]$LogPath
)

$ErrorActionPreference = 'Stop'

# Remote host logging folder for PSWindowsUpdate.
$logDir = Join-Path $env:ProgramData 'PSWindowsUpdate'
New-Item -ItemType Directory -Path $logDir -Force | Out-Null

if ($Worker) {
	# -----------------------------
	# Worker mode: run updates now.
	# -----------------------------
	if ([string]::IsNullOrWhiteSpace($LogPath)) {
		throw 'LogPath is required in -Worker mode.'
	}

	Import-Module PSWindowsUpdate -ErrorAction Stop

	# Always include -AcceptAll -Install.
	$wuArgs = @(
		'-AcceptAll',
		'-Install'
	)

	# Conditionally add optional switches/params.
	if ($AutoReboot) { $wuArgs += '-AutoReboot' }
	if (-not [string]::IsNullOrWhiteSpace($ScheduleJobIso)) {
		$dt = [datetime]::Parse($ScheduleJobIso, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind)
		$wuArgs += @('-ScheduleJob', $dt)
	}
	if (-not [string]::IsNullOrWhiteSpace($ScheduleRebootIso)) {
		$dt = [datetime]::Parse($ScheduleRebootIso, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind)
		$wuArgs += @('-ScheduleReboot', $dt)
	}

	"[{0:o}] Starting Get-WindowsUpdate {1}" -f (Get-Date), ($wuArgs -join ' ') | Out-File -FilePath $LogPath -Append

	try {
		Get-WindowsUpdate @wuArgs -Verbose *>> $LogPath
		"[{0:o}] Completed Get-WindowsUpdate" -f (Get-Date) | Out-File -FilePath $LogPath -Append
	} catch {
		"[{0:o}] ERROR: {1}" -f (Get-Date), $_.Exception.Message | Out-File -FilePath $LogPath -Append
		throw
	}

	return
}

# -----------------------------------------------------------------
# Launcher mode: start a hidden background worker and return.
# -----------------------------------------------------------------
$effectiveScheduleJobIso = if ($PSBoundParameters.ContainsKey('ScheduleJob') -and $null -ne $ScheduleJob) { $ScheduleJob.ToString('o') } else { '' }
$effectiveScheduleRebootIso = if ($PSBoundParameters.ContainsKey('ScheduleReboot') -and $null -ne $ScheduleReboot) { $ScheduleReboot.ToString('o') } else { '' }

$effectiveLogPath = Join-Path $logDir ("RemoteWU-{0:yyyyMMdd-HHmmss}.log" -f (Get-Date))

$selfPath = if (-not [string]::IsNullOrWhiteSpace($PSCommandPath)) { $PSCommandPath } else { $MyInvocation.MyCommand.Path }
if ([string]::IsNullOrWhiteSpace($selfPath)) {
	throw 'Unable to determine script path for relaunch.'
}

$argList = @(
	'-NoProfile',
	'-ExecutionPolicy', 'Bypass',
	'-WindowStyle', 'Hidden',
	'-File', $selfPath,
	'-Worker',
	"-AutoReboot:$AutoReboot",
	'-ScheduleJobIso', $effectiveScheduleJobIso,
	'-ScheduleRebootIso', $effectiveScheduleRebootIso,
	'-LogPath', $effectiveLogPath
)

Start-Process -FilePath powershell.exe -ArgumentList $argList -WindowStyle Hidden | Out-Null

"Started background update worker. Log: $effectiveLogPath" | Write-Output
'@

	# Encode the payload so we can embed it safely inside the remote bootstrap.
	$u1Bytes = [System.Text.Encoding]::Unicode.GetBytes($u1Text)
	$u1Encoded = [Convert]::ToBase64String($u1Bytes)

	# Serialize datetimes as ISO 8601 so parsing is culture-invariant on remote.
	$autoRebootBool = [bool]$AutoReboot
	$scheduleJobIso = if ($PSBoundParameters.ContainsKey('ScheduleJob') -and $null -ne $ScheduleJob) { $ScheduleJob.ToString('o') } else { '' }
	$scheduleRebootIso = if ($PSBoundParameters.ContainsKey('ScheduleReboot') -and $null -ne $ScheduleReboot) { $ScheduleReboot.ToString('o') } else { '' }

	# Convert optional before/after scripts to strings and Base64 them to avoid quoting issues.
	$beforeText = if ($null -eq $ScriptToRunBefore) { '' } elseif ($ScriptToRunBefore -is [scriptblock]) { $ScriptToRunBefore.ToString() } else { [string]$ScriptToRunBefore }
	$afterText = if ($null -eq $ScriptToRunAfter) { '' } elseif ($ScriptToRunAfter -is [scriptblock]) { $ScriptToRunAfter.ToString() } else { [string]$ScriptToRunAfter }

	$beforeEncoded = if (-not [string]::IsNullOrWhiteSpace($beforeText)) { [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($beforeText)) } else { '' }
	$afterEncoded = if (-not [string]::IsNullOrWhiteSpace($afterText)) { [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($afterText)) } else { '' }

	# Build ssh arguments (BatchMode avoids password prompts / hangs).
	$sshArgs = @('-o', 'BatchMode=yes')
	if (-not [string]::IsNullOrWhiteSpace($IdentityFile)) {
		$sshArgs += @('-i', $IdentityFile, '-o', 'IdentitiesOnly=yes')
	}

	foreach ($computer in $RemoteComputers) {
		if ([string]::IsNullOrWhiteSpace($computer)) { continue }

		# Support specifying a global ssh username.
		$sshTarget = if (-not [string]::IsNullOrWhiteSpace($SshUser)) { "$SshUser@$computer" } else { $computer }

		# -----------------------------------------------------------------
		# Remote bootstrap:
		# - runs optional BEFORE script
		# - writes u1 payload to ProgramData
		# - launches u1 (which immediately detaches the update worker)
		# - runs optional AFTER script
		# -----------------------------------------------------------------
		$remoteBootstrap = @"
`$ErrorActionPreference = 'Stop'

`$beforeBase64 = '$beforeEncoded'
`$afterBase64 = '$afterEncoded'

if (-not [string]::IsNullOrWhiteSpace(`$beforeBase64)) {
	`$beforeText = [System.Text.Encoding]::Unicode.GetString([Convert]::FromBase64String(`$beforeBase64))
	Invoke-Expression `$beforeText
}

`$u1Base64 = '$u1Encoded'
`$u1Content = [System.Text.Encoding]::Unicode.GetString([Convert]::FromBase64String(`$u1Base64))

`$dir = Join-Path `$env:ProgramData 'WindowsMachinesGroupUpdate'
New-Item -ItemType Directory -Path `$dir -Force | Out-Null

`$u1Path = Join-Path `$dir 'u1-remote-windows-update.ps1'
Set-Content -LiteralPath `$u1Path -Value `$u1Content -Encoding Unicode -Force

`$jobIso = '$scheduleJobIso'
`$rebootIso = '$scheduleRebootIso'

`$jobDt = if (-not [string]::IsNullOrWhiteSpace(`$jobIso)) { [datetime]::Parse(`$jobIso, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind) } else { `$null }
`$rebootDt = if (-not [string]::IsNullOrWhiteSpace(`$rebootIso)) { [datetime]::Parse(`$rebootIso, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind) } else { `$null }

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File `$u1Path -AutoReboot:$($autoRebootBool) -ScheduleJob `$jobDt -ScheduleReboot `$rebootDt | Out-Null

if (-not [string]::IsNullOrWhiteSpace(`$afterBase64)) {
	`$afterText = [System.Text.Encoding]::Unicode.GetString([Convert]::FromBase64String(`$afterBase64))
	Invoke-Expression `$afterText
}
"@

		# Avoid cmd.exe quoting problems on the remote side by using -EncodedCommand.
		$bootstrapBytes = [System.Text.Encoding]::Unicode.GetBytes($remoteBootstrap)
		$bootstrapEncoded = [Convert]::ToBase64String($bootstrapBytes)
		$remoteCommand = "powershell.exe -NoProfile -ExecutionPolicy Bypass -EncodedCommand $bootstrapEncoded"

		try {
			Write-Host "[$computer] starting remote update (detached)..." -ForegroundColor Cyan
			& ssh @sshArgs $sshTarget $remoteCommand | Out-Null
			Write-Host "[$computer] started" -ForegroundColor Green
		} catch {
			Write-Warning "[$computer] SSH failed: $($_.Exception.Message)"
		}
	}
}

############################################################
# Sample: end-to-end execution
#
# 1) From your admin workstation (where SSH client is available):
#
#   . "./Windows Machines Group Update/fn-RemoteWindowsUpdate.ps1"
#
#   fn-RemoteWindowsUpdate `
#     -RemoteComputers @('server1.contoso.com','10.10.10.25') `
#     -SshUser 'Administrator' `
#     -IdentityFile "$HOME\.ssh\id_ed25519" `
#     -ScriptToRunBefore {
#       Write-Output "Before: $(hostname)"
#       whoami
#     } `
#     -AutoReboot `
#     -ScheduleJob ([datetime]::new(2025,12,30,23,0,0)) `
#     -ScheduleReboot ([datetime]::new(2025,12,31,2,0,0)) `
#     -ScriptToRunAfter {
#       Write-Output "After: update worker was started"
#     }
#
# 2) Expected orchestrator output (example):
#
#   [server1.contoso.com] starting remote update (detached)...
#   [server1.contoso.com] started
#   [10.10.10.25] starting remote update (detached)...
#   [10.10.10.25] started
#
# 3) On each target, the update job writes a log like:
#
#   C:\ProgramData\PSWindowsUpdate\RemoteWU-YYYYMMDD-HHMMSS.log
#
# Notes:
# - ScriptToRunAfter runs after the worker is started (not after updates finish).

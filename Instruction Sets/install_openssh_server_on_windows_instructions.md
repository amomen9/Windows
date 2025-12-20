# Install OpenSSH Server on Windows (Instruction Set)

This guide covers common ways to install and configure the Windows `OpenSSH` server (`sshd`).

> Prerequisites
>
>- Run PowerShell as Administrator.
>- If you change ports, make sure firewall rules match.

---

## Option A: Install via Windows Capability (recommended when available)

1. Install the server capability:

```powershell
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
```

2. Start the service and set it to start automatically:

```powershell
Start-Service sshd
Set-Service -Name sshd -StartupType Automatic
```

3. (Optional) Install the client capability:

```powershell
Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0
```

---

## Option B: Install the Win32-OpenSSH ZIP (manual)

1. Create the target directory:

```powershell
Set-Location "$env:USERPROFILE\Desktop"
New-Item -ItemType Directory -Path "C:\Program Files\OpenSSH" -Force | Out-Null
```

2. Download the latest release ZIP (redirect-based):

```powershell
$url = 'https://github.com/PowerShell/Win32-OpenSSH/releases/latest/'
$request = [System.Net.WebRequest]::Create($url)
$request.AllowAutoRedirect = $false
$response = $request.GetResponse()
$source = $([string]$response.GetResponseHeader('Location')).Replace('tag','download') + '/OpenSSH-Win64.zip'

$webClient = [System.Net.WebClient]::new()
$webClient.DownloadFile($source, (Get-Location).Path + '\OpenSSH-Win64.zip')
```

3. Extract to a temp directory and move to Program Files:

```powershell
Expand-Archive -Path .\OpenSSH-Win64.zip -DestinationPath $env:TEMP -Force
Move-Item "$($env:TEMP)\OpenSSH-Win64\*" -Destination "C:\Program Files\OpenSSH\" -Force
```

4. Unblock downloaded files:

```powershell
Get-ChildItem -Path "C:\Program Files\OpenSSH\" | Unblock-File
```

5. Install the services:

```powershell
& 'C:\Program Files\OpenSSH\install-sshd.ps1'
```

6. Clean up the ZIP:

```powershell
Remove-Item -Path .\OpenSSH-Win64.zip -Force
```

7. Enable and start services:

```powershell
Set-Service -Name ssh-agent -StartupType Automatic
Set-Service -Name sshd -StartupType Automatic

Start-Service ssh-agent
Start-Service sshd
```

---

## Option C: Install from a CAB (offline / staged)

1. Add the package:

```powershell
DISM /Online /Add-Package /PackagePath:"\\tsclient\Cloud Storage\OpenSSH-Server-Package~31bf3856ad364e35~amd64~~.cab"
```

2. Enable and start `sshd`:

```powershell
Get-Service sshd | Set-Service -StartupType Automatic
Start-Service sshd
```

3. Allow inbound SSH in the firewall:

```powershell
New-NetFirewallRule -Name sshd -DisplayName 'OpenSSH Server (sshd)' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22
```

---

## Change SSH port (example: 2222)

1. Update `sshd_config`:

```powershell
$configPath = 'C:\ProgramData\ssh\sshd_config'
(Get-Content $configPath) -replace '#Port 22', 'Port 2222' -replace '^Port 22', 'Port 2222' | Set-Content $configPath
```

2. Restart service:

```powershell
Restart-Service sshd
```

3. Update firewall rule:

```powershell
Remove-NetFirewallRule -Name sshd -ErrorAction SilentlyContinue
New-NetFirewallRule -Name sshd -DisplayName 'OpenSSH Server (sshd)' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 2222
```

4. Verify:

```powershell
Get-Content $configPath | Select-String -Pattern '^Port'
Get-NetFirewallRule -Name sshd | Get-NetFirewallPortFilter
```

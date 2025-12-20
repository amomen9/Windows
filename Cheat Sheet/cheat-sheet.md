# Windows Cheat Sheet

A curated set of commonly used Windows `CMD` and PowerShell commands.

> Notes
>
>- Secrets/credentials in the original text were replaced with placeholders like `<PASSWORD>` and `<TOKEN>`.
>- Some topics that are better expressed as step-by-step guides are documented under [Instruction Sets](../Instruction%20Sets/).

---

## Table of contents

- [Registry tweaks](#registry-tweaks)
- [Apps and packages](#apps-and-packages)
- [SQL Server](#sql-server)
- [Remote execution and credentials](#remote-execution-and-credentials)
- [File transfer and copy](#file-transfer-and-copy)
- [Networking](#networking)
- [Time sync and time zones](#time-sync-and-time-zones)
- [DISM / Windows features](#dism--windows-features)
- [OpenSSH (quick commands)](#openssh-quick-commands)
- [Users and accounts](#users-and-accounts)
- [SIDs (security identifiers)](#sids-security-identifiers)
- [Windows licensing](#windows-licensing)
- [Processes and troubleshooting](#processes-and-troubleshooting)
- [Task Scheduler](#task-scheduler)
- [Hashes](#hashes)
- [System inventory](#system-inventory)
- [Sleep and power](#sleep-and-power)
- [PATH management](#path-management)
- [WMI / WMIC](#wmi--wmic)
- [Firewall](#firewall)
- [Volume Shadow Copy](#volume-shadow-copy)
- [Event IDs (quick reference)](#event-ids-quick-reference)
- [Misc](#misc)

---

## Registry tweaks

### Add apps to Win+R (`App Paths`)

```cmd
reg add "HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths" /f
reg add "HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\ssms.exe" /ve /d "C:\Program Files (x86)\Microsoft SQL Server Management Studio 18\Common7\IDE\Ssms.exe" /f
reg add "HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\devart.exe" /ve /d "D:\Program Files\Devart\dbForge Studio for SQL Server\dbforgesql.exe" /f
```

### Windows 11: enable classic context menu

```cmd
reg add "HKEY_CURRENT_USER\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32" /f
reg add "HKEY_CURRENT_USER\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}" /f
```

---

## Apps and packages

### List installed Win32 and Microsoft Store apps

```powershell
# Win32 (registry)
Get-ItemProperty `
  HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*, `
  HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* `
| Select-Object DisplayName, DisplayVersion, Publisher

# Microsoft Store apps
Get-AppxPackage | Select-Object Name, Version, Publisher
```

### Export installed apps excluding updates/hotfixes

```powershell
# Build Win32 list (registry)
$win32 = Get-ItemProperty `
  HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*, `
  HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* `
| Where-Object { $_.DisplayName -and $_.DisplayName.Trim() -ne '' } `
| Select-Object @{Name='Name';Expression={$_.DisplayName}},
                @{Name='Version';Expression={$_.DisplayVersion}},
                @{Name='Publisher';Expression={$_.Publisher}},
                @{Name='UninstallString';Expression={$_.UninstallString}},
                @{Name='Source';Expression={'Win32'}}

# Build Store list
$store = Get-AppxPackage -AllUsers |
  Select-Object @{Name='Name';Expression={$_.Name}},
                @{Name='Version';Expression={$_.Version}},
                @{Name='Publisher';Expression={$_.Publisher}},
                @{Name='Source';Expression={'Store'}}

# Combine
$combined = $win32 + $store

# 1) Installed KBs
$kbList = Get-HotFix | ForEach-Object { $_.HotFixID }

# 2) Exclusion patterns
$excludePatterns = @(
  'KB\d{5,}',
  '\bUpdate\b',
  'Security Update',
  '\bHotfix\b',
  'Service Pack',
  'Cumulative Update'
) -join '|'
$regex = [regex]::new($excludePatterns, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

# 3) Filter out updates/hotfixes
$filtered = $combined | Where-Object {
  $name = $_.Name -as [string]
  if ($null -eq $name) { $true } else {
    $isUpdateByPattern = $regex.IsMatch($name)
    $containsKB = $kbList | Where-Object { $name -match $_ }
    -not ($isUpdateByPattern -or $containsKB)
  }
}

$filtered | Sort-Object Name |
  Export-Csv -Path "$env:USERPROFILE\Desktop\InstalledApps_NoUpdates.csv" -NoTypeInformation
```

---

## Remote execution and credentials

### Run a process as another user

```cmd
runas /noprofile /env /user:DOMAIN\username "notepad \"my file.txt\""
runas /netonly /user:DOMAIN\username "C:\Program Files (x86)\Microsoft SQL Server Management Studio 19\Common7\IDE\Ssms.exe"
```

### SSH

```shell
# Local port forward
ssh -L <local_port>:<host_or_ip>:<remote_port> <user>@<ssh_host>
```

```powershell
# Append your public key to a remote Linux user's authorized_keys
type $env:USERPROFILE\.ssh\id_rsa.pub | ssh <user>@<host> "cat >> ~/.ssh/authorized_keys"
```

### PsExec (Sysinternals)

```cmd
psexec \\SERVER cmd
psexec -u SERVER\Administrator -p <PASSWORD> \\SERVER cmd
```

### Fix “Access denied” to admin shares / PsExec (UAC remote restrictions)

> This enables full token for local accounts over the network. Use carefully.

```cmd
reg add HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System /v LocalAccountTokenFilterPolicy /t REG_DWORD /d 1 /f
```

```powershell
Restart-Service -Name LanmanServer, LanmanWorkstation -Force
```

---

## File transfer and copy

### Robocopy

```cmd
robocopy "\\SERVER\f$\SomeInstaller.exe" "F:\" /E /IS

# Copy directory tree only (exclude all files)
robocopy "C:\source\path" "C:\destination\path" /E /XF *
```

### Copy a file via admin shares

```cmd
xcopy "\\SOURCE\C$\Users\User\Desktop\file.png" "\\DEST\C$\Users\User\Desktop\n\" /S /Y /F /I
```

### Download a file (curl)

```cmd
curl --output file.exe https://example.com/path/to/installer.exe
curl --output image.png https://upload.wikimedia.org/wikipedia/commons/e/e0/example.png
```

---

## Networking

### Wi‑Fi: show stored profile key

```cmd
netsh wlan show profile name="<SSID>" key=clear | find /i "Key Content"
```

### Mark a Wi‑Fi network as metered/unmetered

```cmd
netsh wlan set profileparameter name="<SSID>" cost=fixed
```

### List/enable/disable network adapters

```cmd
netsh interface set interface "<INTERFACE NAME>" disable
netsh interface set interface "<INTERFACE NAME>" enable
```

```cmd
wmic path win32_networkadapter where index=1 call disable
wmic path win32_networkadapter where index=1 call enable
```

### IP configuration

```cmd
ipconfig /all | findstr /c:"Ethernet"
netsh interface ip show config name="Wi-Fi"
```

### Reset networking stack

```cmd
netsh winsock reset
netsh int ip reset
ipconfig /release
ipconfig /renew
ipconfig /flushdns
shutdown /r /f /t 0
```

### Routing

```cmd
route -p add 10.10.10.0 mask 255.255.255.0 10.10.10.1 metric 10 if 8
route -p add 172.16.0.0 mask 255.255.0.0 192.168.54.1
route delete 10.41.0.0 mask 255.255.0.0
```

### Delete all routes for a specific interface

```cmd
FOR /F "tokens=1,2,3,*" %a IN ('ROUTE PRINT ^| FINDSTR /R "^ *[0-9][0-9]*\."') DO @(
  IF "%d" EQU "<InterfaceIndex>" (
    ROUTE DELETE %a MASK %b %c
  )
)
```

### Port forwarding (portproxy)

```cmd
netsh interface portproxy add v4tov4 listenport=9000 listenaddress=0.0.0.0 connectport=9000 connectaddress=<TARGET_IP>
```

---

## Time sync and time zones

### List and set time zone

```cmd
tzutil /l
tzutil /s "Iran Standard Time"
```

### Time sync

```cmd
net time \\DOMAINSERVER /set /y
w32tm /resync
w32tm /domain
w32tm /config /update /manualpeerlist:time.server.url.com
```

### Fix `w32time` service issues

```cmd
net stop w32time
w32tm /unregister
w32tm /register
net start w32time
w32tm /resync /rediscover
```

---

## DISM / Windows features

```cmd
dism /online /get-features
Dism /online /Get-FeatureInfo /FeatureName:<feature_name>
```

```powershell
Add-WindowsCapability -Online -Name telnet-client
```

```cmd
dism /online /Enable-Feature /FeatureName:TelnetClient
```

---

## SQL Server

### Silent install (example)

```cmd
Setup.exe /PID="AAAAA-BBBBB-CCCCC-DDDDD-EEEEE" /SECURITYMODE=SQL /SAPWD="<SA_PASSWORD>" /ConfigurationFile=SQLServer19_Silent_Installation_Conf_File.ini > C:\sqlsetuplog.txt
```

### Apply a Cumulative Update (CU) (example)

```cmd
"\\SERVER\share\SQLServer2019-KB5007182-x64.exe" /action=patch /instancename=MSSQLSERVER /quiet /IAcceptSQLServerLicenseTerms
```

### SSMS silent install (example)

```cmd
SSMS-Setup-ENU.exe /Quiet SSMSInstallRoot="D:\Tools\SSMS"
```

### SQL Server filesystem tuning (examples)

```cmd
fsutil 8dot3name set 1
fsutil behavior set disablelastaccess 1
```

### Query installed SQL instances (PowerShell)

```powershell
$inst = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server').InstalledInstances
foreach ($i in $inst) {
  $p = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\SQL").$i
  (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\$p\Setup").Edition
  (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\$p\Setup").PatchLevel
}
```

---

## OpenSSH (quick commands)

```powershell
# Install OpenSSH Server capability
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
Start-Service sshd
Set-Service -Name sshd -StartupType Automatic

# Install OpenSSH Client capability
Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0
```

For full installation methods and port changes, see:

- [Install OpenSSH Server on Windows](../Instruction%20Sets/install_openssh_server_on_windows_instructions.md)

---

## Users and accounts

```cmd
net user username /domain
net user USERNAME NewPass
net user USERNAME *

net user Ali <PASSWORD> /add
net localgroup administrators Ali /add

net user administrator /active:yes
```

```cmd
wmic path Win32_UserAccount WHERE Name='admin' set PasswordExpires=false
wmic useraccount where name='username' set PasswordExpires=False
```

---

## SIDs (security identifiers)

```cmd
whoami /user
```

```cmd
wmic useraccount where name='username' get sid
wmic useraccount where sid='S-1-...-...' get name
```

```cmd
dsquery computer -name "MyComputer" | dsget computer -SID
```

---

## Windows licensing

```cmd
slmgr /skms <KMS_SERVER>
slmgr /ato
slmgr /xpr
```

---

## Processes and troubleshooting

### Restart Explorer

```cmd
timeout /t 5 & taskkill /T /F /IM explorer.exe & timeout /t 8 & start explorer.exe
```

### List tasks remotely

```cmd
tasklist /S 192.168.241.4 /nh | sort /R /+65
```

### “watch” equivalent (poll)

```cmd
for /l %g in () do @(tasklist | findstring -i ssms & timeout /t 1)
```

### System file check

```cmd
sfc /scannow
```

---

## Task Scheduler

```cmd
schtasks /create /xml "\\SERVER\share\Task.xml" /tn "TaskName"
schtasks /delete /tn "TaskName" /f
```

---

## Hashes

```powershell
Get-FileHash "C:\Path\To\File" -Algorithm MD5
```

```cmd
forfiles /s /m *.jpg /c "cmd /c CertUtil -hashfile @path MD5"
```

---

## System inventory

### Export a system information report

```cmd
msinfo32 /nfo %userprofile%\Desktop\MySYSInfo.nfo
```

### CPU core counts

```powershell
Get-WmiObject -Class Win32_Processor | Format-Table NumberOfCores,NumberOfLogicalProcessors
```

---

## Sleep and power

### Standby / suspend

```cmd
rundll32.exe powrprof.dll,SetSuspendState 0,1,0
```

```cmd
psshutdown.exe -d -t 0 -accepteula
```

### Powercfg

```cmd
powercfg /batteryreport
powercfg /?
powercfg /? DEVICEDISABLEWAKE
POWERCFG /DEVICEQUERY wake_armed

powercfg /DEVICEDISABLEWAKE "HID-compliant mouse (001)"
```

---

## PATH management

> `setx` writes *persistently*, but the current terminal won’t see it until you open a new session.

```cmd
setx PATH "%PATH%;C:\xampp\php"
setx /M PATH "%PATH%;C:\xampp\php"
```

---

## WMI / WMIC

### Reset WMI repository

```cmd
NET STOP Winmgmt -y
winmgmt /resetrepository
winmgmt /verifyrepository
```

### NIC configuration (export to clipboard)

```cmd
wmic /OUTPUT:CLIPBOARD nicconfig where "IPEnabled='TRUE'" get Caption,MACAddress,IPAddress,IPSubnet,DefaultIPGateway,InterfaceIndex,DNSDomainSuffixSearchOrder
```

---

## Firewall

```powershell
New-NetFirewallRule -DisplayName "SQLPort" -Direction Inbound -LocalPort 2828 -Protocol TCP -Action Allow
```

### Create “any-to-any” allow inbound rule

```powershell
New-NetFirewallRule `
  -DisplayName "Allow ALL Inbound" `
  -Direction Inbound `
  -Action Allow `
  -Protocol Any `
  -LocalAddress Any `
  -RemoteAddress Any `
  -LocalPort Any `
  -RemotePort Any `
  -Enabled True
```

### Query inbound allow rules (example filter)

```powershell
Get-NetFirewallRule -Action Allow -Enabled True -Direction Inbound |
 ForEach-Object {
   $rule = $_
   $addr = Get-NetFirewallAddressFilter -AssociatedNetFirewallRule $rule
   $port = Get-NetFirewallPortFilter   -AssociatedNetFirewallRule $rule

   if ($addr.RemoteAddress -eq 'Any' -and
       $rule.Profile      -in @('Domain, Private, Public','Any') -and
       $rule.DisplayName   -like "*SQL_Access*" -and
       $addr.LocalAddress  -eq 'Any' -and
       $port.Protocol      -in ('Any','UDP','TCP') -and
       $port.RemotePort    -eq 'Any' -and
       $port.LocalPort     -eq 'Any') {

     $props = @{}
     foreach ($obj in @($rule, $addr, $port)) {
       foreach ($p in $obj.PSObject.Properties) {
         $props[$p.Name] = $p.Value
       }
     }
     [PSCustomObject]$props
   }
 } | Select-Object DisplayName, Enabled, Action, Direction, Profile, Priority, Protocol, LocalAddress, LocalPort, RemoteAddress, RemotePort |
   Format-Table
```

---

## Volume Shadow Copy

```cmd
vshadow -p -rw -script=c:\cmd\SETVAR1.cmd d:
vshadow -el=<snapshot_id>,x:
vshadow -bw=<shadow_copy_set_id>
```

---

## Event IDs (quick reference)

```text
Shutdown initiated: 1074 (System log)

Audit authentication:
- Logon success: 4624
- Logon failure: 4625
- Logoff completed: 4634
- Logoff initiated: 4647
- Explicit credentials used: 4648
- User disconnected: 4779

Failover: 2049
```

---

## Misc

### Shell startup folders

```text
shell:startup
shell:common startup
```

### Auto-recovery locations

```text
%userprofile%\AppData\Roaming\Microsoft\Word
%userprofile%\AppData\Local\Microsoft\Office\UnsavedFiles
%userprofile%\AppData\Roaming\Microsoft\Excel
%AppData%\Notepad++\backup
```

### Docker quick start

```cmd
docker run -d -p 80:80 docker/getting-started
```

### Create symbolic links

```cmd
mklink <Link> <Target>
mklink /D <LinkDir> <TargetDir>
mklink /J <JunctionDir> <TargetDir>
mklink /H <HardLink> <TargetFile>
```

### ffmpeg

```shell
# Slice from 1:00 to 2:30 without re-encoding
ffmpeg -i input.mp3 -ss 00:01:00 -to 00:02:30 -c copy output.mp3

# Detect duration
ffprobe -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 input.mp3
```

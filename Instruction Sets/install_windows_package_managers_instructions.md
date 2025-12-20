# Install Windows package managers (Chocolatey, winget) (Instruction Set)

This guide captures the install steps for common Windows package managers.

> Run as Administrator.

---

## Install Chocolatey

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
```

---

## Install/repair winget (DesktopAppInstaller)

```powershell
Get-Process -Name WindowsPackageManagerServer.exe -ErrorAction SilentlyContinue | Stop-Process -Force
Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe
```

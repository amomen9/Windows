# Install PowerShell modules offline (Instruction Set)

This guide shows a practical workflow for downloading PowerShell modules on an online machine and installing them on an offline machine.

> Notes
>
>- PowerShell version should be `5.0+` on the target machine.
>- Prefer copying the module folder into one of the standard module paths.

---

## 1) Prepare the online machine

1. Install/upgrade prerequisite tooling:

```powershell
Install-Module -Name PowerShellGet -RequiredVersion 2.2.5 -Force
Install-Module -Name PackageManagement -Force
Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
```

2. Create a download folder:

```powershell
New-Item -Path 'C:\PowerShellModules' -ItemType Directory -Force | Out-Null
```

3. Download modules into that folder:

```powershell
Save-Module -Name PSReadLine -Path 'C:\PowerShellModules'

# Optional examples
Save-Module -Name PSWindowsUpdate -Path 'C:\PowerShellModules'
```

---

## 2) Copy modules to the offline machine

Copy the downloaded module folder(s) to the offline server.

---

## 3) Install on the offline machine

### Option A (recommended): copy into a module path

1. Discover module search paths:

```powershell
$env:PSModulePath -split ';'
```

2. Copy the module folder into one of the returned directories, for example:

```text
%USERPROFILE%\Documents\WindowsPowerShell\Modules
C:\Program Files\WindowsPowerShell\Modules
C:\WINDOWS\system32\WindowsPowerShell\v1.0\Modules
```

3. Verify:

```powershell
Get-Module -ListAvailable -Name PSReadLine
```

### Option B: install from a local repository path

If you have a local repository layout, you can also install directly (format may vary by repository setup):

```powershell
Install-Module -Name PSReadLine -Repository 'C:\PowerShellModules\PSReadLine'
```

---

## 4) Quick checks

```powershell
$PSVersionTable.PSVersion
Get-Module -ListAvailable | Select-Object -First 10
```

# Elevate a batch file to Administrator (UAC prompt) (Instruction Set)

This guide shows a common pattern to prompt for elevation when a `.cmd`/`.bat` is run without admin rights.

> Use case
>
>- You have a script that must run elevated (e.g., editing protected registry keys).

---

## Option A: Use an embedded VBScript helper (self-elevating batch)

1. Add a UAC elevation block near the top of your batch file.
2. If the script is not running as admin, it will re-launch itself with elevation.

```bat
@echo off
setlocal

:: Check admin rights
NET FILE 1>NUL 2>NUL
if %errorlevel%==0 goto :gotPrivileges

:: Re-run as admin
set "vbs=%temp%\getadmin_%random%.vbs"
echo Set UAC = CreateObject("Shell.Application") > "%vbs%"
echo UAC.ShellExecute "%~fs0", "", "", "runas", 1 >> "%vbs%"
cscript //nologo "%vbs%"
del "%vbs%" >nul 2>&1
exit /b

goto :eof

:gotPrivileges
:: Your elevated code starts here
whoami /groups
```

---

## Option B: Use PowerShell to elevate a batch file

```powershell
Start-Process 'your-batch-file.bat' -Verb RunAs
```

---

## Option C: Use `runas` (limitations)

`runas` does not always behave like UAC elevation for admin tasks, but for some cases:

```cmd
runas /user:Administrator "your-batch-file.bat"
```

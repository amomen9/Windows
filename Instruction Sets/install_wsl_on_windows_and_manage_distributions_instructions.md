# Install WSL on Windows and manage distributions (Instruction Set)

This guide collects the WSL installation and management steps from the original cheat sheet.

> Notes
>
>- `wsl --install` is the simplest path on modern Windows.
>- Some commands run inside Linux (WSL). Those are labeled as `bash`.

---

## 1) Install WSL

### Option A (recommended): Microsoft Store / `wsl --install`

1. Install WSL and (by default) Ubuntu:

```powershell
wsl --install
```

2. If you want to install WSL but skip installing a default distro:

```powershell
wsl --install --no-distribution
```

### Option B: Enable required Windows features via DISM

1. Enable WSL feature:

```powershell
dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart
```

2. Enable Virtual Machine Platform:

```powershell
dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart
```

---

## 2) (Optional) Update the WSL kernel package

```powershell
wsl --update
```

If `wsl --update` is not available/working in your environment, you can install the update MSI manually:
- `https://wslstorestorage.blob.core.windows.net/wslblob/wsl_update_x64.msi`

---

## 3) Inspect status and installed distros

```powershell
wsl -v
wsl --status
wsl -l -v

wsl --list --online
wsl --list --all
```

---

## 4) Install a distribution

```powershell
wsl --install -d <DistroName>

# Example
wsl --install -d Ubuntu-20.04
```

---

## 5) Common management commands

```powershell
# Run a specific distro
wsl -d <DistroName>

# Set default distro
wsl -s <DistroName>

# Set default WSL version
wsl --set-default-version 2

# Run with a specific user
wsl --distribution <DistroName> --user <UserName>

# Terminate a distro
wsl --terminate <DistroName>

# Shutdown all WSL instances
wsl --shutdown
```

---

## 6) Where WSL distros live (Windows-side)

Installed distro packages typically live under:

```text
%userprofile%\AppData\Local\Packages
```

---

## 7) Find host IP as seen by WSL2

Run inside WSL:

```bash
cat /etc/resolv.conf | grep nameserver | awk '{print $2}'
```

# Configure WSL resources, DNS, and backups (Instruction Set)

This guide covers `.wslconfig`, `wsl.conf`, DNS tweaks, and export/import operations.

---

## 1) Create or ensure `.wslconfig` exists

Run in PowerShell:

```powershell
if (-not (Test-Path -Path (Join-Path -Path $env:USERPROFILE -ChildPath '.wslconfig'))) {
  New-Item -Path $env:USERPROFILE -Name '.wslconfig' -ItemType File | Out-Null
} else {
  Write-Output "The file '.wslconfig' already exists."
}
```

---

## 2) Limit resources for all WSL2 VMs

Edit `%USERPROFILE%\.wslconfig` and add something like:

```ini
[wsl2]
memory=2GB
processors=2
```

---

## 3) Change DNS inside WSL

### Option A: Set a nameserver via `.wslconfig`

```ini
[wsl2]
nameserver = 8.8.8.8, 8.8.4.4
```

### Option B: Use `wsl.conf` + `resolv.conf` (per-distro)

1. Inside WSL, edit `/etc/wsl.conf`:

```bash
sudo vi /etc/wsl.conf
```

2. Add:

```ini
[network]
generateResolvConf = false
```

3. Edit `/etc/resolv.conf`:

```bash
sudo vi /etc/resolv.conf
```

4. Add:

```text
nameserver 8.8.8.8
nameserver 8.8.4.4
```

---

## 4) Export, import, and unregister distributions

> Make sure the distro is not running.

1. Export a distro to a tar:

```powershell
wsl --export <DistroName> <path>\backup.tar

# Example
wsl --export OracleLinux_9_1 "D:\WSL\Backups\OracleLinux_9_1.tar"
```

2. Import a new distro from a tar:

```powershell
wsl --import <NewDistroName> <InstallPath> <TarPath> --version 2

# Example
wsl --import OracleLinux9 "D:\WSL\OracleLinux9" "D:\WSL\Backups\OracleLinux_9_1.tar"
```

3. Import in place (VHDX):

```powershell
wsl --import-in-place <NewDistroName> <PathToVhdx>
```

4. Remove (unregister) a distro:

```powershell
wsl --unregister <DistroName>
```

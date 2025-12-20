# Enable PowerShell remoting and run commands remotely (Instruction Set)

This guide collects common WinRM/PowerShell Remoting steps.

---

## 1) Check whether WinRM/PSRemoting is enabled

```powershell
Test-WSMan -ComputerName localhost
```

---

## 2) Enable PSRemoting on the target machine

```powershell
Enable-PSRemoting -Force
```

---

## 3) Run a command remotely

```powershell
Invoke-Command -ComputerName <RemotePC> -ScriptBlock { Get-Process } -Credential <RemoteUser>
```

---

## 4) Disable PSRemoting (if needed)

```powershell
Disable-PSRemoting -Force
```

> Disabling doesn’t always revert everything automatically. If you need a full rollback, you may also need to:
>
>- Stop/disable WinRM.
>- Remove listeners.
>- Remove firewall exceptions.
>- Reset `LocalAccountTokenFilterPolicy`.

---

## 5) Run the same script on multiple servers (example)

```powershell
Enable-PSRemoting -Force

$servers = @('Server1', 'Server2', 'Server3')
$sessions = New-PSSession -ComputerName $servers

$scriptBlock = {
  Write-Output "Running script on $env:COMPUTERNAME"
}

Invoke-Command -Session $sessions -ScriptBlock $scriptBlock
Remove-PSSession -Session $sessions
```

---

## 6) Configure WinRM on a custom port (example: 5895)

```powershell
Enable-PSRemoting -Force
winrm quickconfig -force

# Create a listener on port 5895
winrm create winrm/config/Listener?Address=*+Transport=HTTP '@{Port="5895"; Enabled="true"}'

# Open firewall
New-NetFirewallRule -DisplayName "Allow WinRM on 5895" -Direction Inbound -Protocol TCP -LocalPort 5895 -Action Allow

# Verify
winrm enumerate winrm/config/listener
Get-Service -Name WinRM

# Connect
Enter-PSSession -ComputerName <RemoteHost> -Port 5895
```

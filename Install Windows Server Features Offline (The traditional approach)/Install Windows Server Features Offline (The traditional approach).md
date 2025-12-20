# Install Windows Server Features Offline

In the event that installing packages using Add-WindowsCapability or dism is not possible due to any reason and policy for example
 when Windows is set to receive packages via WSUS, Internet connectivity is not available, etc instead of using the common commands
 
 `Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0`
 
 `dism /Online /Add-Capability /CapabilityName:OpenSSH.Server~~~~0.0.1.0`
 
We use downloading the packages and installing them offline method. 

Here, we must make certain of several factors:

* The downloaded and transferred packages to the servers are absolutely reliable and threat-free. In the sense of what we want to
 do here which is installing windows features offline, we use the packages provided by Microsoft itself, because first they are 
 definitely virus-free, second we intend the features that are provided by Microsoft in this document
 
* The packages are stable and production-ready.

If your Windows Server version is 2022 and later, one **very viable candidate** is the Microsoft Application Compatibility `Feature on Demand (FOD)` packages that can be downloaded
 from the following Microsoft link:
 
[Install Server Core Application Compatibility Feature on Demand | Microsoft Learn](https://learn.microsoft.com/en-us/windows-server/get-started/server-core-app-compatibility-feature-on-demand?tabs=windows-update)

Download the respective ISO image file (for example, for Windows Server 2022) and mount it to your Windows machine.
 If your Windows Server version is 2019 and earlier, the packages might not be obtainable this way.
 You might need to check other locations like the official GitHub repositories.

### Installing features:

If you need to install the packages offline, first you need to transfer them to the server.

Download the respective iso according to your Windows Server version, then mount it. In the mounted image
 files, search for the feature you want. For example, OpenSSH. Identify the `.cab` file by searching
 `OpenSSH` in the mounted image and copy its path.

You can run the following:

```cmd
DISM /Online /Add-Package /PackagePath:"<package path>"
```

to install the package. 

Subsequently, do whatever actions that are needed after the installation of the package.
 For example, for OpenSSH-Server, you need to start the service and set it to start up automatically on boot.
  You can do that by using the following commands:
  
```PowerShell
# Start the installed service
Start-Service sshd
# Set the service startup-type to automatic
Set-Service -Name sshd -StartupType 'Automatic'
```

Optionally, change the OpenSSH Server default port:


1. Edit the SSH configuration file
notepad C:\ProgramData\ssh\sshd_config

2. Perform other modifications

```PowerShell
# New port value
$port=2222

# Remove old firewall rule
Remove-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue

# Add new firewall rule for the new port
New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH Server (sshd)' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort $port

# Restart SSH service to apply changes
Restart-Service sshd

# Verify the service is listening on the new port
Get-NetTCPConnection -LocalPort $port -State Listen
```

-

### Read more:

[Features On Demand | Microsoft Learn](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/features-on-demand-v2--capabilities?view=windows-11)

[Get started with OpenSSH Server for Windows | Microsoft Learn](https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh_install_firstuse?tabs=gui&pivots=windows-server-2022)
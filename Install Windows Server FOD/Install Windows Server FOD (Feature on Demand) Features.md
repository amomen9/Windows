# Install Feature on Demand features on Microsoft Windows Server

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

### Installing features:

If you need to install the packages offline, first you need to transfer them to the server. On the following
 link you can find the iso image containing the packages for Windows Server:
 
[Install Server Core Application Compatibility Feature on Demand | Microsoft Learn](https://learn.microsoft.com/en-us/windows-server/get-started/server-core-app-compatibility-feature-on-demand?tabs=windows-update)

Download the respective iso according to your Windows Server version, then mount it. In the mounted image
 files, search for the feature you want. For example, OpenSSH. Identify the `.cab` file.

Suppose the drive letter of the mounted image is "G:\". In that case, you can run 

```cmd
DISM /Online /Add-Package /PackagePath:"G:\LanguagesAndOptionalFeatures\OpenSSH-Server-Package~31bf3856ad364e35~amd64~~.cab"
```

to install the package. Subsequently, do whatever actions that are needed after the installation of the package.
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

# Windows
Windows docs, PowerShell, and CMD commands

## PowerShell Version

The scripts are compatible with PowerShell version `5` and later

---

### 1. logoff user (local computer).ps1

This very simple script demonstrates how to extract the session Id of an account and pass it to the logoff command at will
 to log off that user. Obviously, admin rights are required to log off other users' sessions. The log off command only accepts
 the user's session Id.
 
--- 
 
### 2. Execute Logout on Remote Servers Serializably 

This script is the development of the 1st script to execute logoff command on as many remote servers as you desire. This is very
 helpfull when you change your domain password and have some disconnected sessions running and are not sure on which servers they
 are. Such occasion most likely will result in constant and perpetual lock out of your account because of the multiple wrong password
 entry of your user by the open sessions which can be very annoying.

This script can also be used as a report to identify the users that have logged into your servers.

This script can both report the servers with your logged on sessions and also execute remote logoff command for your or
 someone else's session.

---

### 3. Execute Logout on Remote Servers in Parallel 

This script is the development of the 2nd script to execute logoff command on as many remote servers as you desire. This is very
 helpfull when you change your domain password and have some disconnected sessions running and are not sure on which servers they
 are. Such occasion most likely will result in constant and perpetual lock out of your account because of the multiple wrong password
 entry of your user by the open sessions which can be very annoying.

This script can also be used as a report to identify the users that have logged into your servers.

This script can both report the servers with your logged on sessions and also execute remote logoff command for you or
 someone else's session.
 
The input "$user" parameter can be a regular expression. The found results per server can be a list of any users matching the search pattern "$user"

*Sample output for $user = ".":*

![users parallel](image/Picture2.png)

---

<!--
4. Execute any Script on Remote Servers in Parallel:

Execute any script on multiple remote servers in parallel
-->

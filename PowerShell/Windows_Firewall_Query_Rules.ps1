# This script is designed to query and filter Windows Firewall Rules and give comprehensive data about the found rules



clear
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
       $port.LocalPort     -eq 'Any'
       
       ) {
     
     $props = @{}
 
     # 3. Merge properties from each object
     foreach ($obj in @($rule, $addr, $port)) {
         foreach ($p in $obj.PSObject.Properties) {
             # If a property name already exists, you can choose to skip, overwrite,
             # or rename. Here we overwrite with the last one encountered.
             $props[$p.Name] = $p.Value
         }
     }
 
     [PSCustomObject]$props
  
   }
 } | Select-Object DisplayName, Enabled, Action, Direction, Profile, Priority, Protocol, LocalAddress, LocalPort, LocalIP, RemoteAddress, RemoteIP, RemotePort, PolicyStoreSourceType, Description |
   | Format-Table

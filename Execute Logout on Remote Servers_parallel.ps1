
################################################################
## Author: Ali Momen                                          ##
## Email: amomen@gmail.com                                    ##
## GitHub User: amomen9                                       ##
## Script: Execute Logout on Remote Servers_parallel.ps1      ##
## Language: PowerShell (5<)                                  ##
################################################################


########################## PARAMETERS ##########################

## The username and password used to authenticate to all of the target servers
$username = 'domain.com\a.momen'
$password = 'P@@S$sW0rd'
## The target servers IP/NS Name
$servers=@(
"<IP1>", "<IP2>", "<NS Name1>", "<NS Name2>" 
)
## The regex pattern based on which the users sessions are looked up for on the target servers. For example $user='men' will
## find the users like "a.momen" or "a.momen@domain" or "moremen" (it is similar to my last name :D) or "morewomen"
$user = 'a.ma';
## Choose whether you also want to logoff the user(s) or not. Write "yes" or "no"
$logoff_user="no"
## Choose "yes" if you want to show a message for the servers with no matching results or "no" if you want to print nothing for them
## in the terminal
$show_servers_with_no_matching_results="yes"

################################################################




##------- install ThreadJob for parallel execution of the loop items --------
if (-not (Get-Module -ListAvailable -Name ThreadJob)) {
    Install-Module -Name ThreadJob -Force -Scope CurrentUser
} 
Import-Module ThreadJob
##---------------------------------------------------------------------------


##-------------------------- clean terminal ---------------------------------
cls

##------------- Begin caluculating script execution time---------------------
$startTime = Get-Date
Write-Host "Start Time: $startTime`n#########`n" -ForegroundColor Yellow

##------------- Begin script body: ------------------------------------------
$password = ConvertTo-SecureString $password -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential($username, $password)

$failedSessions = @()

"Number of Servers: " + $servers.Count


$count_criteria_found=0
$count_criteria_not_found=0

$counter=0
$jobs=@()

foreach ($server in $servers) {

    $counter++
    $jobName = "($counter/$($servers.count)) "+"$server"
    $job = Start-ThreadJob -Name $jobName -ArgumentList $server, $cred, $user, $show_servers_with_no_matching_results, $logoff_user, $counter -ScriptBlock { 
        param($server, $cred, $user, $show_servers_with_no_matching_results, $logoff_user, $counter)

        try {
    

            $session = New-PSSession -ComputerName $server -Credential $cred -ErrorAction Stop        
            
            $output = Invoke-Command -Session $session -ArgumentList $user, $show_servers_with_no_matching_results, $logoff_user, $counter -ScriptBlock {
            
                        
                param($user, $show_servers_with_no_matching_results, $logoff_user, $counter)
            
                
                $sessions = (query user | Select-Object -Skip 1 | Where-Object { $_ -match $user }) 2>$null;
                $output = @{ 
                    ServerName = ""                               # Equal per iteration
                    users_found = @()                             # Equal per iteration
                    LogoffMessage_session_only_print = ""         # Equal per iteration
                    LogoffMessage_session_print_and_logoff = ""   # Equal per iteration
                    LogoffMessage_no_session = ""                 # Equal per iteration
                    count_criteria_found = 0 # Integer type       # Varying per iteration
                    count_criteria_not_found = 0 # Integer type   # Varying per iteration
                    is_failed=0                                   # Equal per iteration
                    failedsession=@()                             # Equal per iteration
                    #MatchList = @() # Array type                 # Equal per iteration
                }                
                

                $output.ServerName = "`n$env:COMPUTERNAME",":"

                if([string]::IsNullOrEmpty($sessions)) {

                    if($show_servers_with_no_matching_results -eq "yes") {
                  
                        $output.LogoffMessage_no_session = "No logged-in session was found for a username matching the given pattern `"$user`"."
                    }

                    $output.count_criteria_not_found+=1
                
                    return $output

                }
                $output.count_criteria_found+=1

                foreach ($session in $sessions) { # Perform an action with each $process Write-Output $process.ProcessName 
               
                    $session = $session.Trim(); 

                    if ($session) 
                    { 

                        $tokens = $session -split '\s+';

                        $sessionId=$tokens[1];
                
                        $output.users_found += $tokens[0].Trim(); #+': '+$sessionId                                                   
                    }


                    if($logoff_user -eq "yes"){
                        logoff $sessionId
                        $output.LogoffMessage_session_print_and_logoff = "Logoff session command executed for the user $output.users_found"
                    } else {
                        $output.LogoffMessage_session_only_print = "`nUser is not logged off because `$logoff_user is set to `"no`""           
                    }                                        
                }


                return $output            
            } #-Credential $cred

            

        


            if ([string]::IsNullOrEmpty($output.users_found)){
                if ($show_servers_with_no_matching_results -eq "yes"){
                    Write-Host "`n`n$($output.ServerName)" -ForegroundColor Magenta
                    Write-Host $output.LogoffMessage_no_session -ForegroundColor DarkYellow -NoNewLine
                }
            } else {
      
                Write-Host "`n$($output.ServerName)" -ForegroundColor Magenta
                #Write-Host "$($output.users_found)" -ForegroundColor Green
                $output.users_found | ForEach-Object { Write-Host $_ -ForegroundColor Green }

                if (-not [string]::IsNullOrEmpty($output.LogoffMessage_session_print_and_logoff)) {
                    Write-Host $output.LogoffMessage_session_print_and_logoff -ForegroundColor DarkRed -NoNewLine
                }
                if (-not [string]::IsNullOrEmpty($output.LogoffMessage_session_only_print)) {
                    Write-Host $output.LogoffMessage_session_only_print -ForegroundColor Gray -NoNewLine
                }        
            }

            Remove-PSSession -Session $session
        } catch {
            
            $output = @{ 
                ServerName = "" 
                users_found = @() 
                LogoffMessage_session_only_print = "" 
                LogoffMessage_session_print_and_logoff = "" 
                LogoffMessage_no_session = "" 
                count_criteria_found = 0 # Integer type 
                count_criteria_not_found = 0 # Integer type 
                is_failed=0
                failedsession=@()
                #MatchList = @() # Array type 
            }

            $output.failedSession = [PSCustomObject]@{
                Server = $server
                ErrorMessage = $_.Exception.Message
            }
        }
    
        return $output
    }
    
    $jobs+=$job
    

}

# Wait for all jobs to complete 
$jobs | ForEach-Object {
    $job = Wait-Job -Job $_

    # Adjust the lengths of each property
    $name = $job.Name.PadRight(25).Substring(0, 25)
    $type = $job.PSJobTypeName.PadRight(20).Substring(0, 20)
    $state = $job.State.PadRight(10).Substring(0, 10)
    
    # Create a custom object with the formatted properties
    [PSCustomObject]@{
        Name = $name
        PSJobTypeName = $type
        State = $state
    }
} | Select-Object Name, PSJobTypeName, State

# Get the results 
$outputs = ($jobs | ForEach-Object { Receive-Job -Job $_ })
# Clean up the jobs 
$jobs | ForEach-Object { Remove-Job -Job $_ } #> $null

foreach ($output in $outputs) {

    
    $count_criteria_found+=$output["count_criteria_found"]
    $count_criteria_not_found+=$output["count_criteria_not_found"]
   
    if (-not [string]::IsNullOrEmpty($output["failedsession"])) {
        $failedSessions+=$output["failedsession"]
    }
    
    
}



Write-Host "`n`n`n`n$($servers.count) total servers processed
$count_criteria_found servers had sessions with the given criteria
$count_criteria_not_found servers did not match the criteria
$($failedSessions.Count) servers were out of reach`n`n"


if ($failedSessions.Count -gt 0) {
    Write-Host "----------------------------------`nSome connections failed:" -ForegroundColor Red
    $failedSessions | Format-Table -AutoSize
} else {
    Write-Host "----------------------------------`nAll connections were successful." -ForegroundColor Green
}



##----------------- Printing out the execution time ------------------------
$endTime = Get-Date 
Write-Host "`n`n`n#########`nEnd Time: $endTime" -ForegroundColor Yellow
$duration = $endTime - $startTime 
Write-Host "Total Duration: $($duration.TotalSeconds) seconds" -ForegroundColor Yellow
##--------------------------------------------------------------------------
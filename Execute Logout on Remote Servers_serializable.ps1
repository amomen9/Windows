
################################################################
## Author: Ali Momen                                          ##
## Email: amomen@gmail.com                                    ##
## GitHub User: amomen9                                       ##
################################################################


########################## PARAMETERS ##########################

## The username and password used to authenticate to all of the target servers
$username = 'domain.com\a.momen'
$password = 'P@@S$sW0rd'
## The target servers IP/NS Name
$servers=@(
"<IP1>", "<IP2>", "<NS Name1>", "<NS Name2>" 
)
## The pattern based on which the users sessions are looked up for on the target servers. For example $user='men' will
## find the users like "a.momen" or "a.momen@domain" or "moremen" or "morewomen"
$user = 'mome';
## Choose whether you also want to logoff the user(s) or not. Write "yes" or "no"
$logoff_user="no"
## Choose "yes" if you want to show a message for the servers with no matching results or "no" if you want to print nothing for them
## in the terminal
$show_servers_with_no_matching_results="yes"

################################################################



##-------------------------- clean PowerShell terminal ------------------
cls

##------------- Begin caluculating script execution time-----------------
$startTime = Get-Date
Write-Host "Start Time: $startTime`n#########`n" -ForegroundColor Yellow

##------------- Begin script body: --------------------------------------
$password = ConvertTo-SecureString $password -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential($username, $password)

$failedSessions = @()

"Number of Servers: " + $servers.Count

$count_criteria_found=0
$count_criteria_not_found=0


##-------------------- Loop through servers -----------------------------
foreach ($server in $servers) {

    try {
    


        $session = New-PSSession -ComputerName $server -Credential $cred -ErrorAction Stop

        
        $output = Invoke-Command -Session $session -ArgumentList $user, $show_servers_with_no_matching_results, $logoff_user -ScriptBlock {
            
            
            
            param($user, $show_servers_with_no_matching_results, $logoff_user)
            
            
            $session = (query user | Where-Object { $_ -match $user }) 2>$null;
            $output = @{ 
                ServerName = "" 
                user_found = "" 
                LogoffMessage_session_only_print = "" 
                LogoffMessage_session_print_and_logoff = "" 
                LogoffMessage_no_session = "" 
                count_criteria_found = 0 # Integer type 
                count_criteria_not_found = 0 # Integer type 
                #MatchList = @() # Array type 
            }
            $output.ServerName = "`n`n$env:COMPUTERNAME",":"
            if([string]::IsNullOrEmpty($session)) {

                if($show_servers_with_no_matching_results -eq "yes") {
                      
                    $output.LogoffMessage_no_session = "No logged-in session was found for a username matching $user."
                }

                $output.count_criteria_not_found+=1
                
                return $output

            }
            $output.count_criteria_found+=1
               
            $session = $session.Trim(); 

            if ($session) 
            { 

                $tokens = $session -split '\s+';

                $sessionId=$tokens[1];
                
                $output.user_found = $tokens[0].Trim(); #+': '+$sessionId

                                 
                if($logoff_user -eq "yes"){
                    logoff $sessionId
                    $output.LogoffMessage_session_print_and_logoff = "Logoff session command executed for the user $output.user_found"
                } else {
                    $output.LogoffMessage_session_only_print = "User is not logged off because `$logoff_user is set to `"no`""           
                }
                  
            }
            return $output
            
        } #-Credential $cred


        #Write-Output $output
        
        $count_criteria_found+=$output.count_criteria_found
        $count_criteria_not_found+=$output.count_criteria_not_found
        

        if ([string]::IsNullOrEmpty($output.user_found)){
            if ($show_servers_with_no_matching_results -eq "yes"){
                Write-Host "`n`n$($output.ServerName)" -ForegroundColor Magenta
                Write-Host $output.LogoffMessage_no_session -ForegroundColor DarkYellow -NoNewLine
            }
        } else {
      
            Write-Host "`n$($output.ServerName)" -ForegroundColor Magenta
            Write-Host "$($output.user_found)" -ForegroundColor Green


            if (-not [string]::IsNullOrEmpty($output.LogoffMessage_session_print_and_logoff)) {
                Write-Host $output.LogoffMessage_session_print_and_logoff -ForegroundColor DarkRed -NoNewLine
            }
            if (-not [string]::IsNullOrEmpty($output.LogoffMessage_session_only_print)) {
                Write-Host $output.LogoffMessage_session_only_print -ForegroundColor Gray -NoNewLine
            }        
        }

        Remove-PSSession -Session $session
    } catch {
        $failedSessions += [PSCustomObject]@{
            Server = $server
            ErrorMessage = $_.Exception.Message
        }
    }
}


Write-Host "`n`n`nTotal servers processed were $servers.count`n`n$count_criteria_found servers had sessions with the given criteria`n$count_criteria_not_found servers did not match the criteria`n`n$failedSessions.Count servers were out of reach`n`n"


if ($failedSessions.Count -gt 0) {
    Write-Host "`n----------------------------------`nSome connections failed:" -ForegroundColor Red
    $failedSessions | Format-Table -AutoSize
} else {
    Write-Host "`n----------------------------------`nAll connections were successful." -ForegroundColor Green
}



##----------------- Printing out the execution time --------------------
$endTime = Get-Date 
Write-Host "`n`n`n#########`nEnd Time: $endTime" -ForegroundColor Yellow
$duration = $endTime - $startTime 
Write-Host "Total Duration: $($duration.TotalSeconds) seconds" -ForegroundColor Yellow
##----------------------------------------------------------------------

# Assign a part of the user name to the variable $user and make sure that the pattern only matches your intended users
# You can comment out the line 'logoff $sessionId' to first view the logged on users that are found which their name
# matches $user pattern. After confirming that the results are the desired ones, uncomment that line to log off the user.

$user = 'Al'; 
$session = query user | Where-Object { $_ -match $user }; 
if ($session) 
{ 
    $tokens = $session -split '\s+'; $sessionId=$tokens[2]; 
    $user = $tokens[0].Substring(1,$tokens[0].Length-1).Trim(); 
    $user+': '+$sessionId
    #logoff $sessionId 
}

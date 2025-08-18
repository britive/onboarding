# Origincal code by Will. I added the logic to terminate the RDP session upon checkin.

$email = $env:user_email
$username = $email.Split('@')[0]
$username = $username.Substring(0, [Math]::Min($username.Length, 16))
$username = "$username-rec"

# Function to kill active RDP sessions for a given user
function KillRDPSessions {
    param (
        [Parameter(Mandatory = $true)]
        [string]$username
    )

    try {
        $qwinstaOutput = qwinsta $username
        $lines = $qwinstaOutput -split "`r`n"
        $userLines = $lines | Where-Object { $_ -match "\b$username\b" }
        $sessionIds = $userLines | ForEach-Object {
            $fields = $_ -split '\s+'
            if ($fields.Count -ge 3) {
                $fields[3]
            }
        }
    }
    catch {
        $sessionIds = @()
    }

    foreach ($session in $sessionIds) {
        Invoke-RDUserLogoff -HostServer localhost -UnifiedSessionID $session -Force
    }
}

# Only log off the user — do NOT delete!
KillRDPSessions -Username $username

# Commenting out user deletion to preserve account and profile
# CleanUpLocalUser -Username $username

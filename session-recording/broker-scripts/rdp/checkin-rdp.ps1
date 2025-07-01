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

# Function to remove a local user from the machine
function CleanUpLocalUser {
  param (
    [Parameter(Mandatory = $true)]
    [string]$username
  )

  try {
    # Get the local user object
    $user = Get-LocalUser -Name $username -ErrorAction Stop

    # Remove the local user
    Write-Output "Removing local user: $username"
    $user | Remove-LocalUser -ErrorAction Stop
  }
  catch {
    Write-Error "Error removing local user: $_"
  }
}

KillRDPSessions -Username $username

CleanUpLocalUser -Username $username

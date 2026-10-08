# Check-in: runs on the Windows target itself. Logs off every session of the
# temporary user created by checkout-rdp.ps1 and removes the account.
#
# Environment: user_email

$email = $env:user_email
$username = $email.Split('@')[0]
$username = $username.Substring(0, [Math]::Min($username.Length, 16))
$username = "$username-rec"

# Log off every session of the user. qwinsta prints
#   [SESSIONNAME]  USERNAME  ID  STATE ...
# and SESSIONNAME is blank for disconnected sessions, so the ID is taken from
# the number that follows the username rather than from a fixed column.
function KillRDPSessions {
  param (
    [Parameter(Mandatory = $true)]
    [string]$username
  )

  $sessionIds = @()
  try {
    $pattern = '\s' + [regex]::Escape($username) + '\s+(\d+)\s'
    foreach ($line in ((qwinsta 2>$null) -split "`r?`n")) {
      if ($line -match $pattern) { $sessionIds += $Matches[1] }
    }
  }
  catch {
    $sessionIds = @()
  }

  # Invoke-RDUserLogoff only exists with the RemoteDesktop module (RDS role);
  # plain Windows hosts fall back to logoff.exe.
  $haveRdCmdlet = [bool](Get-Command Invoke-RDUserLogoff -ErrorAction SilentlyContinue)
  foreach ($sessionId in $sessionIds) {
    $done = $false
    if ($haveRdCmdlet) {
      try {
        Invoke-RDUserLogoff -HostServer localhost -UnifiedSessionID $sessionId -Force -ErrorAction Stop
        $done = $true
      }
      catch {}
    }
    if (-not $done) { logoff $sessionId 2>$null }
  }
}

# Remove the local user
function CleanUpLocalUser {
  param (
    [Parameter(Mandatory = $true)]
    [string]$username
  )

  try {
    $user = Get-LocalUser -Name $username -ErrorAction Stop
    Write-Output "Removing local user: $username"
    $user | Remove-LocalUser -ErrorAction Stop
  }
  catch {
    Write-Error "Error removing local user: $_"
    exit 1
  }
}

KillRDPSessions -Username $username

CleanUpLocalUser -Username $username

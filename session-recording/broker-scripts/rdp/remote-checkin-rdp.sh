#!/bin/bash
# Check-in: runs on the broker, connects to the remote Windows host over WinRM,
# logs off any session of the temporary user and removes the account.
#
# Pair with remote-checkout-rdp.sh; takes the same WINRM_* variables
# (WINRM_SCHEME http|https, WINRM_TRANSPORT basic|ntlm, WINRM_PORT,
# WINRM_CERT_VALIDATION validate|ignore).

set -u
set -o errexit
set -o pipefail

# ==============================
# Configurable Variables
# ==============================
USER_EMAIL=${BRITIVE_USER_EMAIL:-"test@example.com"}
USERNAME="${USER_EMAIL%%@*}"
USERNAME="${USERNAME//[^a-zA-Z0-9]/}"
TARGET_USER="${USERNAME:0:16}-rec"

REMOTE_HOST="${BRITIVE_REMOTE_HOST:-}"
WINRM_USER="${WINRM_USER:-"Administrator"}"
WINRM_PASSWORD="${WINRM_PASSWORD:-}"
WINRM_SCHEME="${WINRM_SCHEME:-http}"
WINRM_TRANSPORT="${WINRM_TRANSPORT:-basic}"
WINRM_CERT_VALIDATION="${WINRM_CERT_VALIDATION:-validate}"

# ==============================
# Fail-fast checks
# ==============================
[[ -z "$REMOTE_HOST" ]] && { echo "ERROR: BRITIVE_REMOTE_HOST is not set" >&2; exit 1; }
[[ -z "$WINRM_PASSWORD" ]] && { echo "ERROR: WINRM_PASSWORD is not set" >&2; exit 1; }

case "$WINRM_SCHEME" in
  http)  WINRM_PORT="${WINRM_PORT:-5985}" ;;
  https) WINRM_PORT="${WINRM_PORT:-5986}" ;;
  *) echo "ERROR: WINRM_SCHEME must be http or https" >&2; exit 1 ;;
esac
case "$WINRM_TRANSPORT" in
  basic|ntlm) ;;
  *) echo "ERROR: WINRM_TRANSPORT must be basic or ntlm" >&2; exit 1 ;;
esac
case "$WINRM_CERT_VALIDATION" in
  validate|ignore) ;;
  *) echo "ERROR: WINRM_CERT_VALIDATION must be validate or ignore" >&2; exit 1 ;;
esac

# ==============================
# Log off RDP sessions and remove user via WinRM
# Secrets reach Python through its environment, never through the script text.
# ==============================
WINRM_RESULT=$(
  WINRM_URL="${WINRM_SCHEME}://${REMOTE_HOST}:${WINRM_PORT}/wsman" \
  WINRM_USER="$WINRM_USER" \
  WINRM_PASSWORD="$WINRM_PASSWORD" \
  WINRM_TRANSPORT="$WINRM_TRANSPORT" \
  WINRM_CERT_VALIDATION="$WINRM_CERT_VALIDATION" \
  TARGET_USER="$TARGET_USER" \
  python3 - <<'PYEOF'
import os
import sys
import winrm


def ps_quote(value):
    """Single-quote a value for PowerShell (no interpolation inside '...')."""
    return "'" + value.replace("'", "''") + "'"


session = winrm.Session(
    os.environ['WINRM_URL'],
    auth=(os.environ['WINRM_USER'], os.environ['WINRM_PASSWORD']),
    transport=os.environ['WINRM_TRANSPORT'],
    server_cert_validation=os.environ['WINRM_CERT_VALIDATION'],
)

ps_script = (
    "$username = " + ps_quote(os.environ['TARGET_USER']) + "\n"
    r"""
# Log off every session of this user. qwinsta prints
#   [SESSIONNAME]  USERNAME  ID  STATE ...
# and SESSIONNAME is blank for disconnected sessions, so the ID is taken from
# the number that follows the username rather than from a fixed column.
$sessionIds = @()
try {
    $pattern = '\s' + [regex]::Escape($username) + '\s+(\d+)\s'
    foreach ($line in ((qwinsta 2>$null) -split "`r?`n")) {
        if ($line -match $pattern) { $sessionIds += $Matches[1] }
    }
} catch {}

$haveRdCmdlet = [bool](Get-Command Invoke-RDUserLogoff -ErrorAction SilentlyContinue)
foreach ($sessionId in $sessionIds) {
    $done = $false
    if ($haveRdCmdlet) {
        try {
            Invoke-RDUserLogoff -HostServer localhost -UnifiedSessionID $sessionId -Force -ErrorAction Stop
            $done = $true
        } catch {}
    }
    if (-not $done) { logoff $sessionId 2>$null }
}

# Remove the local user
if (Get-LocalUser -Name $username -ErrorAction SilentlyContinue) {
    Remove-LocalUser -Name $username -ErrorAction Stop | Out-Null
    Write-Output "REMOVED"
} else {
    Write-Output "NOT_FOUND"
}
"""
)

result = session.run_ps(ps_script)
if result.status_code != 0:
    sys.stderr.write('ERROR: ' + result.std_err.decode('utf-8', errors='replace') + '\n')
    sys.exit(1)

print(result.std_out.decode('utf-8', errors='replace').strip())
PYEOF
)

if [[ "$WINRM_RESULT" == "REMOVED" ]]; then
  echo "INFO: User '${TARGET_USER}' removed from ${REMOTE_HOST}"
elif [[ "$WINRM_RESULT" == "NOT_FOUND" ]]; then
  echo "INFO: User '${TARGET_USER}' not found on ${REMOTE_HOST} - already removed"
else
  echo "ERROR: Unexpected result from ${REMOTE_HOST}: $WINRM_RESULT" >&2
  exit 1
fi

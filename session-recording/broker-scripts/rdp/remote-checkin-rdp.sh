#!/bin/bash

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

REMOTE_HOST="$BRITIVE_REMOTE_HOST"
WINRM_USER="${WINRM_USER:-"Administrator"}"
WINRM_PASSWORD="${WINRM_PASSWORD}"
WINRM_PORT="${WINRM_PORT:-5985}"

# ==============================
# Fail-fast checks
# ==============================
[[ -z "$REMOTE_HOST" ]] && { echo "ERROR: BRITIVE_REMOTE_HOST is not set"; exit 1; }
[[ -z "${WINRM_PASSWORD:-}" ]] && { echo "ERROR: WINRM_PASSWORD is not set"; exit 1; }

# ==============================
# Kill RDP sessions and remove user via WinRM
# ==============================
WINRM_RESULT=$(python3 - <<PYEOF
import winrm, sys

session = winrm.Session(
    'http://${REMOTE_HOST}:${WINRM_PORT}/wsman',
    auth=('${WINRM_USER}', '${WINRM_PASSWORD}'),
    transport='basic',
)

ps_script = r"""
\$username = '${TARGET_USER}'

# Kill any active RDP sessions for this user
try {
    \$sessions = qwinsta \$username 2>\$null
    if (\$sessions) {
        \$sessions -split "\`r\`n" | Where-Object { \$_ -match "\b\$username\b" } | ForEach-Object {
            \$fields = \$_ -split '\s+'
            if (\$fields.Count -ge 3) {
                \$sessionId = \$fields[3]
                try { Invoke-RDUserLogoff -HostServer localhost -UnifiedSessionID \$sessionId -Force -ErrorAction Stop }
                catch { logoff \$sessionId /server:localhost 2>\$null }
            }
        }
    }
} catch {}

# Remove the local user
if (Get-LocalUser -Name \$username -ErrorAction SilentlyContinue) {
    Remove-LocalUser -Name \$username -ErrorAction Stop | Out-Null
    Write-Output "REMOVED"
} else {
    Write-Output "NOT_FOUND"
}
"""

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
  echo "INFO: User '${TARGET_USER}' not found on ${REMOTE_HOST} — already removed"
else
  echo "ERROR: Unexpected result from ${REMOTE_HOST}: $WINRM_RESULT" >&2
  exit 1
fi

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
# Windows local username: up to 16 chars of prefix + "-rec" suffix = max 20 chars (Windows limit)
TARGET_USER="${USERNAME:0:16}-rec"

REMOTE_HOST="$BRITIVE_REMOTE_HOST"
WINRM_USER="${WINRM_USER:-"Administrator"}"
WINRM_PASSWORD="${WINRM_PASSWORD}"
WINRM_PORT="${WINRM_PORT:-5985}"

SECRET_KEY=${SECRET}

# ==============================
# Fail-fast checks
# ==============================
[[ -z "$REMOTE_HOST" ]] && { echo "ERROR: BRITIVE_REMOTE_HOST is not set"; exit 1; }
[[ -z "${WINRM_PASSWORD:-}" ]] && { echo "ERROR: WINRM_PASSWORD is not set"; exit 1; }
if [[ -z "${SECRET_KEY:-}" ]]; then
  echo "ERROR: SECRET is not set"; exit 1
fi
if ! [[ "$SECRET_KEY" =~ ^[0-9A-Fa-f]{32}$ ]]; then
  echo "ERROR: SECRET must be a 32 hex character string (16 bytes)"; exit 1
fi

# ==============================
# Generate random password
# Satisfies Windows complexity: upper, lower, digit, special
# ==============================
USER_PASSWORD=$(python3 -c "
import secrets, string, sys

upper  = string.ascii_uppercase
lower  = string.ascii_lowercase
digits = string.digits
special = '@#\$%^&+=_'
all_chars = upper + lower + digits + special

pw = [
    secrets.choice(upper),
    secrets.choice(lower),
    secrets.choice(digits),
    secrets.choice(special),
]
pw += [secrets.choice(all_chars) for _ in range(12)]

# shuffle using secrets-backed random
indices = list(range(len(pw)))
for i in range(len(indices) - 1, 0, -1):
    j = secrets.randbelow(i + 1)
    indices[i], indices[j] = indices[j], indices[i]

print(''.join(pw[i] for i in indices))
")

# ==============================
# Create / update Windows local user via WinRM
# ==============================
WINRM_RESULT=$(python3 - <<PYEOF
import winrm, sys

session = winrm.Session(
    'http://${REMOTE_HOST}:${WINRM_PORT}/wsman',
    auth=('${WINRM_USER}', '${WINRM_PASSWORD}'),
    transport='basic',
)

ps_script = r"""
\$username    = '${TARGET_USER}'
\$password    = ConvertTo-SecureString '${USER_PASSWORD}' -AsPlainText -Force
\$fullName    = '${USER_EMAIL}'
\$description = 'Local admin account created by Britive'

if (Get-LocalUser -Name \$username -ErrorAction SilentlyContinue) {
    Set-LocalUser -Name \$username -Password \$password | Out-Null
} else {
    New-LocalUser -Name \$username -Password \$password -FullName \$fullName -Description \$description | Out-Null
}

if (-not (Get-LocalGroupMember -Group 'Administrators' -Member \$username -ErrorAction SilentlyContinue)) {
    Add-LocalGroupMember -Group 'Administrators' -Member \$username | Out-Null
}

Write-Output 'OK'
"""

result = session.run_ps(ps_script)
if result.status_code != 0:
    sys.stderr.write('ERROR: ' + result.std_err.decode('utf-8', errors='replace') + '\n')
    sys.exit(1)

output = result.std_out.decode('utf-8', errors='replace').strip()
print(output)
PYEOF
)

if [[ "$WINRM_RESULT" != "OK" ]]; then
  echo "ERROR: Windows user setup failed on $REMOTE_HOST: $WINRM_RESULT" >&2
  exit 1
fi

# ==============================
# Generate Guacamole RDP token
# ==============================
JSON_STRING='{
  "username": "'${USER_EMAIL}'",
  "expires": "'$(date -d "+${expiration:-3600} seconds" +%s)'000",
  "connections": {
    "'${connection_name}'": {
      "protocol": "rdp",
      "parameters": {
        "hostname": "'${REMOTE_HOST}'",
        "port": "'${port:-3389}'",
        "username": "'${TARGET_USER}'",
        "password": "'${USER_PASSWORD}'",
        "security": "nla",
        "ignore-cert": "true",
        "create-recording-path": "true",
        "recording-include-keys": "true",
        "recording-path": "'${recording_path:-/home/guacd/recordings}'/${HISTORY_UUID}",
        "recording-name": "${GUAC_DATE}-${GUAC_TIME}-'${USER_EMAIL}'-'${TARGET_USER}'-'${connection_name}'"
      }
    }
  }
}'

JSON=$(echo -n "$JSON_STRING" | jq -r tostring)

sign() {
    echo -n "${JSON}" | openssl dgst -sha256 -mac HMAC -macopt hexkey:"${SECRET_KEY}" -binary
    echo -n "${JSON}"
}

encrypt() {
    openssl enc -aes-128-cbc -K "${SECRET_KEY}" -iv "00000000000000000000000000000000" -nosalt -a
}

TOKEN=$(sign | encrypt | tr -d "\n\r" | jq -Rr @uri)

echo -n '{"token": "'${TOKEN}'", "url": "'${url}'"}'

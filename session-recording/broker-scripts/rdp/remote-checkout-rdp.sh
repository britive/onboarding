#!/bin/bash
# Checkout: runs on the broker, connects to a remote Windows host over WinRM,
# creates (or resets) a temporary local administrator, and returns a signed
# Guacamole token that opens a recorded RDP session with those credentials.
#
# Pair with remote-checkin-rdp.sh.
#
# WinRM connection (all optional except WINRM_PASSWORD):
#   WINRM_USER             admin account used for WinRM      default Administrator
#   WINRM_PASSWORD         its password (mark secret in Britive)
#   WINRM_SCHEME           http | https                      default http
#   WINRM_PORT             default 5985 for http, 5986 for https
#   WINRM_TRANSPORT        basic | ntlm                      default basic
#   WINRM_CERT_VALIDATION  validate | ignore (https only)    default validate
# Prefer https + ntlm; basic over http sends the admin password in the clear.

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

REMOTE_HOST="${BRITIVE_REMOTE_HOST:-}"
WINRM_USER="${WINRM_USER:-"Administrator"}"
WINRM_PASSWORD="${WINRM_PASSWORD:-}"
WINRM_SCHEME="${WINRM_SCHEME:-http}"
WINRM_TRANSPORT="${WINRM_TRANSPORT:-basic}"
WINRM_CERT_VALIDATION="${WINRM_CERT_VALIDATION:-validate}"

SECRET_KEY=${SECRET:-}

CONNECTION_NAME="${connection_name:-}"
EXPIRATION="${expiration:-3600}"
GUAC_URL="${url:-}"
RDP_PORT="${port:-3389}"
RECORDING_PATH="${recording_path:-/home/guacd/recordings}"

# ==============================
# Fail-fast checks
# ==============================
[[ -z "$REMOTE_HOST" ]] && { echo "ERROR: BRITIVE_REMOTE_HOST is not set" >&2; exit 1; }
[[ -z "$WINRM_PASSWORD" ]] && { echo "ERROR: WINRM_PASSWORD is not set" >&2; exit 1; }
[[ -z "$CONNECTION_NAME" ]] && { echo "ERROR: connection_name is not set" >&2; exit 1; }
[[ -z "$GUAC_URL" ]] && { echo "ERROR: url is not set" >&2; exit 1; }
if [[ -z "$SECRET_KEY" ]]; then
  echo "ERROR: SECRET is not set" >&2; exit 1
fi
if ! [[ "$SECRET_KEY" =~ ^[0-9A-Fa-f]{32}$ ]]; then
  echo "ERROR: SECRET must be a 32 hex character string (16 bytes)" >&2; exit 1
fi

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
# Generate random password
# Satisfies Windows complexity: upper, lower, digit, special
# ==============================
USER_PASSWORD=$(python3 -c "
import secrets, string

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
for i in range(len(pw) - 1, 0, -1):
    j = secrets.randbelow(i + 1)
    pw[i], pw[j] = pw[j], pw[i]

print(''.join(pw))
")

# ==============================
# Create / update Windows local user via WinRM
# Secrets reach Python through its environment, never through the script text.
# ==============================
WINRM_RESULT=$(
  WINRM_URL="${WINRM_SCHEME}://${REMOTE_HOST}:${WINRM_PORT}/wsman" \
  WINRM_USER="$WINRM_USER" \
  WINRM_PASSWORD="$WINRM_PASSWORD" \
  WINRM_TRANSPORT="$WINRM_TRANSPORT" \
  WINRM_CERT_VALIDATION="$WINRM_CERT_VALIDATION" \
  TARGET_USER="$TARGET_USER" \
  USER_PASSWORD="$USER_PASSWORD" \
  USER_EMAIL="$USER_EMAIL" \
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
    "$username    = " + ps_quote(os.environ['TARGET_USER']) + "\n"
    "$password    = ConvertTo-SecureString " + ps_quote(os.environ['USER_PASSWORD']) + " -AsPlainText -Force\n"
    "$fullName    = " + ps_quote(os.environ['USER_EMAIL']) + "\n"
    "$description = 'Local admin account created by Britive'\n"
    r"""
if (Get-LocalUser -Name $username -ErrorAction SilentlyContinue) {
    Set-LocalUser -Name $username -Password $password | Out-Null
} else {
    New-LocalUser -Name $username -Password $password -FullName $fullName -Description $description | Out-Null
}

if (-not (Get-LocalGroupMember -Group 'Administrators' -Member $username -ErrorAction SilentlyContinue)) {
    Add-LocalGroupMember -Group 'Administrators' -Member $username | Out-Null
}

Write-Output 'OK'
"""
)

result = session.run_ps(ps_script)
if result.status_code != 0:
    sys.stderr.write('ERROR: ' + result.std_err.decode('utf-8', errors='replace') + '\n')
    sys.exit(1)

print(result.std_out.decode('utf-8', errors='replace').strip())
PYEOF
)

if [[ "$WINRM_RESULT" != "OK" ]]; then
  echo "ERROR: Windows user setup failed on $REMOTE_HOST: $WINRM_RESULT" >&2
  exit 1
fi

# ==============================
# Generate Guacamole RDP token
# ==============================
EXPIRES="$(date -d "+${EXPIRATION} seconds" +%s)000"

# ${HISTORY_UUID}, ${GUAC_DATE} and ${GUAC_TIME} are Guacamole tokens and must
# reach Guacamole literally, so they are single-quoted here.
JSON=$(jq -cn \
  --arg username "$USER_EMAIL" \
  --arg expires "$EXPIRES" \
  --arg name "$CONNECTION_NAME" \
  --arg hostname "$REMOTE_HOST" \
  --arg port "$RDP_PORT" \
  --arg user "$TARGET_USER" \
  --arg password "$USER_PASSWORD" \
  --arg recpath "${RECORDING_PATH}"'/${HISTORY_UUID}' \
  --arg recname '${GUAC_DATE}-${GUAC_TIME}-'"${USER_EMAIL}-${TARGET_USER}-${CONNECTION_NAME}" \
  '{
    username: $username,
    expires: $expires,
    connections: {
      ($name): {
        protocol: "rdp",
        parameters: {
          hostname: $hostname,
          port: $port,
          username: $user,
          password: $password,
          security: "nla",
          "ignore-cert": "true",
          "create-recording-path": "true",
          "recording-include-keys": "true",
          "recording-path": $recpath,
          "recording-name": $recname
        }
      }
    }
  }')

sign() {
  echo -n "${JSON}" | openssl dgst -sha256 -mac HMAC -macopt hexkey:"${SECRET_KEY}" -binary
  echo -n "${JSON}"
}

encrypt() {
  openssl enc -aes-128-cbc -K "${SECRET_KEY}" -iv "00000000000000000000000000000000" -nosalt -a
}

TOKEN=$(sign | encrypt | tr -d "\n\r" | jq -Rr @uri)

jq -cn --arg token "$TOKEN" --arg url "$GUAC_URL" '{token: $token, url: $url}'

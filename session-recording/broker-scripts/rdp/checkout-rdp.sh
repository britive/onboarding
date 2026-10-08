#!/bin/bash
# Token-only RDP checkout for an existing domain or local account: nothing is
# created on the target and there is no check-in. The user authenticates to
# the Windows host with their own password; Guacamole records the session.
#
# Required: BRITIVE_USER_EMAIL, hostname, connection_name, url, SECRET_KEY
# Optional: port (3389), domain, security (nla), ignore_cert (true),
#           expiration (3600), recording_path (/home/guacd/recordings)

set -u
set -o errexit
set -o pipefail

USER_EMAIL=${BRITIVE_USER_EMAIL:-"test@example.com"}
USERNAME="${USER_EMAIL%%@*}"
USERNAME="${USERNAME//[^a-zA-Z0-9.]/}"

TARGET_HOST="${hostname:-}"
RDP_PORT="${port:-3389}"
DOMAIN="${domain:-${DOMAIN:-}}"
SECURITY="${security:-nla}"
IGNORE_CERT="${ignore_cert:-true}"
CONNECTION_NAME="${connection_name:-}"
EXPIRATION="${expiration:-3600}"
GUAC_URL="${url:-}"
RECORDING_PATH="${recording_path:-/home/guacd/recordings}"
SECRET_KEY="${SECRET_KEY:-}"

[[ -z "$TARGET_HOST" ]] && { echo "ERROR: hostname is not set" >&2; exit 1; }
[[ -z "$CONNECTION_NAME" ]] && { echo "ERROR: connection_name is not set" >&2; exit 1; }
[[ -z "$GUAC_URL" ]] && { echo "ERROR: url is not set" >&2; exit 1; }
if ! [[ "$SECRET_KEY" =~ ^[0-9A-Fa-f]{32}$ ]]; then
  echo "ERROR: SECRET_KEY must be a 32 hex character string (16 bytes)" >&2; exit 1
fi

EXPIRES="$(date -d "+${EXPIRATION} seconds" +%s)000"

# ${GUAC_DATE} and ${GUAC_TIME} are Guacamole tokens and must reach Guacamole
# literally, so they are single-quoted here.
JSON=$(jq -cn \
  --arg username "$USER_EMAIL" \
  --arg expires "$EXPIRES" \
  --arg name "$CONNECTION_NAME" \
  --arg hostname "$TARGET_HOST" \
  --arg port "$RDP_PORT" \
  --arg security "$SECURITY" \
  --arg ignorecert "$IGNORE_CERT" \
  --arg user "$USERNAME" \
  --arg domain "$DOMAIN" \
  --arg recpath "$RECORDING_PATH" \
  --arg recname '${GUAC_DATE}-${GUAC_TIME}-'"${USER_EMAIL}-${USERNAME}-${CONNECTION_NAME}" \
  '{
    username: $username,
    expires: $expires,
    connections: {
      ($name): {
        protocol: "rdp",
        parameters: ({
          hostname: $hostname,
          port: $port,
          security: $security,
          "ignore-cert": $ignorecert,
          username: $user,
          "recording-path": $recpath,
          "recording-name": $recname
        } + (if $domain == "" then {} else {domain: $domain} end))
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

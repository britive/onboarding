#!/bin/bash
# Checkout: runs on the broker, SSHes to a remote Linux host as the service
# account, creates (or reuses) a local user there, installs a per-checkout SSH
# key tagged with the Britive transaction ID, and returns a signed Guacamole
# token that opens a recorded SSH session to that host.
#
# Pair with remote-checkin-ssh.sh. Both must use the same host-key policy:
# new hosts are accepted on first contact and pinned in /root/.ssh/known_hosts,
# which is bind-mounted from docker/broker-ssh/ so it survives restarts.

set -u  # error on unset vars
set -o errexit
set -o pipefail

# ==============================
# Configurable Variables
# ==============================
USER_EMAIL=${BRITIVE_USER_EMAIL:-"test@example.com"}
USERNAME="${USER_EMAIL%%@*}"
USERNAME="${USERNAME//[^a-zA-Z0-9]/}"

TARGET_USER=${USERNAME}
TARGET_GROUP=${BRITIVE_USER_GROUP:-${USERNAME}}
SUDO_FLAG=${BRITIVE_SUDO:-"0"}
HOME_ROOT=${BRITIVE_HOME_ROOT:-"home"}

REMOTE_USER="britivebroker"  # service account on the target host
REMOTE_HOST="${BRITIVE_REMOTE_HOST:-}"
REMOTE_PORT="${port:-22}"
REMOTE_KEY="/root/.ssh/id_rsa"  # broker SSH key, bind-mounted from docker/broker-ssh/
KNOWN_HOSTS="/root/.ssh/known_hosts"

SECRET_KEY=${SECRET:-}

TRX=${TRX:-"britive-trx-id"}  # Transaction ID marker

CONNECTION_NAME="${connection_name:-}"
EXPIRATION="${expiration:-3600}"
GUAC_URL="${url:-}"
RECORDING_PATH="${recording_path:-/home/guacd/recordings}"

SSH_OPTS=(
  -i "$REMOTE_KEY"
  -o IdentitiesOnly=yes
  -o StrictHostKeyChecking=accept-new
  -o "UserKnownHostsFile=$KNOWN_HOSTS"
  -p "$REMOTE_PORT"
)

# ==============================
# Fail-fast checks
# ==============================
[[ -z "$REMOTE_HOST" ]] && { echo "ERROR: BRITIVE_REMOTE_HOST is not set" >&2; exit 1; }
[[ -z "$CONNECTION_NAME" ]] && { echo "ERROR: connection_name is not set" >&2; exit 1; }
[[ -z "$GUAC_URL" ]] && { echo "ERROR: url is not set" >&2; exit 1; }
[[ ! -f "$REMOTE_KEY" ]] && { echo "ERROR: SSH key not found at $REMOTE_KEY" >&2; exit 1; }
if [[ -z "$SECRET_KEY" ]]; then
  echo "ERROR: SECRET is not set" >&2; exit 1
fi
if ! [[ "$SECRET_KEY" =~ ^[0-9A-Fa-f]{32}$ ]]; then
  echo "ERROR: SECRET must be a 32 hex character string (16 bytes)" >&2; exit 1
fi

# ==============================
# Temp directory + cleanup
# ==============================
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

SSH_KEY_LOCAL="$TMP_DIR/britive-id_rsa"
SSH_KEY_PUB="$TMP_DIR/britive-id_rsa.pub"

# ==============================
# Generate SSH keypair
# ==============================
ssh-keygen -q -N '' -t rsa -C "$USER_EMAIL" -f "$SSH_KEY_LOCAL" || {
  echo "ERROR: Failed to generate SSH keypair" >&2
  exit 1
}

# ==============================
# Create user and setup on remote server
# ==============================
if ! ssh "${SSH_OPTS[@]}" "$REMOTE_USER@$REMOTE_HOST" \
  TARGET_USER="$TARGET_USER" TARGET_GROUP="$TARGET_GROUP" SUDO_FLAG="$SUDO_FLAG" HOME_ROOT="$HOME_ROOT" bash -s <<'EOF'
set -e

SSH_PATH=/${HOME_ROOT}/${TARGET_USER}/.ssh

# Create user if missing
if ! id "${TARGET_USER}" &>/dev/null; then
  sudo /usr/sbin/useradd -m "${TARGET_USER}" || { echo "ERROR: Failed to create user ${TARGET_USER}" >&2; exit 1; }
fi

# Ensure group exists
if ! getent group "${TARGET_GROUP}" >/dev/null 2>&1; then
  sudo groupadd "${TARGET_GROUP}" || true
fi
sudo usermod -g "${TARGET_GROUP}" "${TARGET_USER}" >/dev/null 2>&1 || true

# Ensure .ssh dir exists with correct permissions
sudo mkdir -p "${SSH_PATH}"
sudo chmod 700 "${SSH_PATH}"
sudo chown "${TARGET_USER}:${TARGET_GROUP}" "${SSH_PATH}"

# Optional: grant passwordless sudo
if [ "${SUDO_FLAG}" != "0" ]; then
  echo "${TARGET_USER} ALL=(ALL) NOPASSWD:ALL" | sudo tee "/etc/sudoers.d/${TARGET_USER}" >/dev/null || exit 1
  sudo chmod 440 "/etc/sudoers.d/${TARGET_USER}"
fi
EOF
then
  echo "ERROR: Remote user setup failed on $REMOTE_HOST" >&2
  exit 1
fi

# ==============================
# Copy public key with TRX marker to remote
# ==============================
PUB_KEY_WITH_MARKER="$(cat "$SSH_KEY_PUB") # britive-$TRX"
echo "$PUB_KEY_WITH_MARKER" > "$TMP_DIR/britive-id_rsa_marker.pub"

# scp takes the same options as ssh except that the port flag is -P
if ! scp -q "${SSH_OPTS[@]/#-p/-P}" \
  "$TMP_DIR/britive-id_rsa_marker.pub" \
  "$REMOTE_USER@$REMOTE_HOST:/tmp/britive-id_rsa_marker.pub"; then
  echo "ERROR: Failed to copy public key to $REMOTE_HOST" >&2
  exit 1
fi

# ==============================
# Append to authorized_keys
# ==============================
if ! ssh "${SSH_OPTS[@]}" "$REMOTE_USER@$REMOTE_HOST" \
  TARGET_USER="$TARGET_USER" TARGET_GROUP="$TARGET_GROUP" HOME_ROOT="$HOME_ROOT" bash -s <<'EOF'
set -e

SSH_PATH=/${HOME_ROOT}/${TARGET_USER}/.ssh

sudo bash -c "cat /tmp/britive-id_rsa_marker.pub >> ${SSH_PATH}/authorized_keys"
sudo rm -f /tmp/britive-id_rsa_marker.pub
sudo chmod 600 "${SSH_PATH}/authorized_keys"
sudo chown "${TARGET_USER}:${TARGET_GROUP}" "${SSH_PATH}/authorized_keys"
EOF
then
  echo "ERROR: Failed to update authorized_keys for $TARGET_USER on $REMOTE_HOST" >&2
  exit 1
fi

# ==============================
# Generate Guacamole token
# ==============================
SSH_KEY=$(cat "$SSH_KEY_LOCAL")
EXPIRES="$(date -d "+${EXPIRATION} seconds" +%s)000"

# ${HISTORY_UUID}, ${GUAC_DATE} and ${GUAC_TIME} are Guacamole tokens and must
# reach Guacamole literally, so they are single-quoted here.
JSON=$(jq -cn \
  --arg username "$USER_EMAIL" \
  --arg expires "$EXPIRES" \
  --arg name "$CONNECTION_NAME" \
  --arg hostname "$REMOTE_HOST" \
  --arg port "$REMOTE_PORT" \
  --arg user "$TARGET_USER" \
  --arg key "$SSH_KEY" \
  --arg recpath "${RECORDING_PATH}"'/${HISTORY_UUID}' \
  --arg recname '${GUAC_DATE}-${GUAC_TIME}-'"${USER_EMAIL}-${USERNAME}-${CONNECTION_NAME}" \
  '{
    username: $username,
    expires: $expires,
    connections: {
      ($name): {
        protocol: "ssh",
        parameters: {
          hostname: $hostname,
          port: $port,
          username: $user,
          "private-key": $key,
          "create-recording-path": "true",
          "recording-include-keys": "true",
          "recording-path": $recpath,
          "typescript-path": $recpath,
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

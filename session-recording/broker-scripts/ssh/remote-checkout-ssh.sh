#!/bin/bash

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

REMOTE_USER="britivebroker"  # default SSH user on target EC2
REMOTE_HOST="$BRITIVE_REMOTE_HOST"
REMOTE_KEY="/root/.ssh/id_rsa"  # path to broker SSH key

SECRET_KEY=${SECRET}

TRX=${TRX:-"britive-trx-id"}  # Transaction ID marker

# ==============================
# Fail-fast checks
# ==============================
[[ -z "$REMOTE_HOST" ]] && { echo "ERROR: BRITIVE_REMOTE_HOST is not set"; exit 1; }
[[ ! -f "$REMOTE_KEY" ]] && { echo "ERROR: SSH key not found at $REMOTE_KEY"; exit 1; }
if [[ -z "${SECRET_KEY:-}" ]]; then
  echo "ERROR: SECRET is not set"; exit 1
fi
if ! [[ "$SECRET_KEY" =~ ^[0-9A-Fa-f]{32}$ ]]; then
  echo "ERROR: SECRET must be a 32 hex character string (16 bytes)"; exit 1
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
if ! ssh -i "$REMOTE_KEY" -o IdentitiesOnly=yes -o StrictHostKeyChecking=no \
  "$REMOTE_USER@$REMOTE_HOST" \
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
  echo "${TARGET_USER} ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/${TARGET_USER} >/dev/null || exit 1
  sudo chmod 440 /etc/sudoers.d/${TARGET_USER}
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

if ! scp -q -i "$REMOTE_KEY" -o IdentitiesOnly=yes -o StrictHostKeyChecking=no \
  "$TMP_DIR/britive-id_rsa_marker.pub" \
  "$REMOTE_USER@$REMOTE_HOST:/tmp/britive-id_rsa_marker.pub"; then
  echo "ERROR: Failed to copy public key to $REMOTE_HOST" >&2
  exit 1
fi

# ==============================
# Append to authorized_keys
# ==============================
if ! ssh -i "$REMOTE_KEY" -o IdentitiesOnly=yes -o StrictHostKeyChecking=no \
  "$REMOTE_USER@$REMOTE_HOST" \
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
if [[ ! -f "$SSH_KEY_LOCAL" ]]; then
  echo "ERROR: Private key not found at $SSH_KEY_LOCAL" >&2
  exit 1
fi

SSH_KEY=$(cat "$SSH_KEY_LOCAL")

JSON_STRING='{
  "username": "'${USER_EMAIL}'",
  "expires": "'$(date -d "+${expiration} seconds" +%s)'000",
  "connections": {
    "'${connection_name}'": {
      "protocol": "ssh",
      "parameters": {
        "hostname": "'${REMOTE_HOST}'",
        "port": "22",
        "username": "'${TARGET_USER}'",
        "private-key": "'${SSH_KEY//$'\n'/\\n}'",
        "create-recording-path": "true",
        "recording-include-keys": "true",
        "recording-path": "'${recording_path:-/home/guacd/recordings}'/${HISTORY_UUID}",
        "typescript-path": "'${recording_path:-/home/guacd/recordings}'/${HISTORY_UUID}",
        "recording-name": "${GUAC_DATE}-${GUAC_TIME}-'${USER_EMAIL}'-'${USERNAME}'-'${connection_name}'"
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

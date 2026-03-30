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

TARGET_USER=${USERNAME}
TARGET_GROUP=${BRITIVE_USER_GROUP:-${USERNAME}}
SUDO_FLAG=${BRITIVE_SUDO:-"0"}
HOME_ROOT=${BRITIVE_HOME_ROOT:-"home"}

REMOTE_USER="britivebroker"
REMOTE_HOST="$BRITIVE_REMOTE_HOST"
REMOTE_KEY="/root/.ssh/id_rsa"

TRX=${TRX:-"britive-trx-id"}

# Set to "1" to remove the user and home dir when no Britive keys remain
CLEANUP_USER=${BRITIVE_CLEANUP_USER:-"0"}

# ==============================
# Fail-fast checks
# ==============================
[[ -z "$REMOTE_HOST" ]] && { echo "ERROR: BRITIVE_REMOTE_HOST is not set"; exit 1; }
[[ ! -f "$REMOTE_KEY" ]] && { echo "ERROR: SSH key not found at $REMOTE_KEY"; exit 1; }

# ==============================
# Remove key by TRX marker and clean up user if no keys remain
# ==============================
if ! ssh -i "$REMOTE_KEY" -o IdentitiesOnly=yes -o StrictHostKeyChecking=no \
  "$REMOTE_USER@$REMOTE_HOST" \
  TARGET_USER="$TARGET_USER" TARGET_GROUP="$TARGET_GROUP" \
  SUDO_FLAG="$SUDO_FLAG" HOME_ROOT="$HOME_ROOT" TRX="$TRX" CLEANUP_USER="$CLEANUP_USER" bash -s <<'EOF'
set -e

SSH_PATH="/${HOME_ROOT}/${TARGET_USER}/.ssh"
AUTH_KEYS="${SSH_PATH}/authorized_keys"
MARKER="britive-${TRX}"

if [[ ! -f "$AUTH_KEYS" ]]; then
  echo "INFO: authorized_keys not found for ${TARGET_USER} — already cleaned up"
  exit 0
fi

# Remove the line containing this TRX marker
sudo sed -i "/${MARKER}/d" "$AUTH_KEYS"

echo "INFO: Removed key with marker '${MARKER}' from ${AUTH_KEYS}"

REMAINING=$(sudo grep -c . "$AUTH_KEYS" 2>/dev/null || true)

if [[ "$CLEANUP_USER" == "1" ]]; then
  if [[ "$REMAINING" -eq 0 ]]; then
    echo "INFO: No keys remaining and CLEANUP_USER=1 — removing user ${TARGET_USER}"

    if [[ "$SUDO_FLAG" != "0" ]]; then
      sudo rm -f "/etc/sudoers.d/${TARGET_USER}"
    fi

    sudo pkill -u "${TARGET_USER}" 2>/dev/null || true
    sudo /usr/sbin/userdel -r "${TARGET_USER}" 2>/dev/null || true
  else
    echo "INFO: ${REMAINING} key(s) still present — user ${TARGET_USER} retained"
  fi
else
  echo "INFO: CLEANUP_USER=0 — user ${TARGET_USER} retained (${REMAINING} key(s) remaining)"
fi
EOF
then
  echo "ERROR: Checkin failed on $REMOTE_HOST" >&2
  exit 1
fi

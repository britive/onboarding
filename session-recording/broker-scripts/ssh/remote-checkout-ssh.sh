#!/bin/bash

# ==============================
# Configurable Variables
# ==============================
USER_EMAIL=${BRITIVE_USER_EMAIL:-"test@example.com"}
USERNAME="${USER_EMAIL%%@*}"
USERNAME="${USERNAME//[^a-zA-Z0-9]/}"

USER=${USERNAME}
GROUP=${USERNAME}
SUDO=${BRITIVE_SUDO:-"0"}
HOME_ROOT=${BRITIVE_HOME_ROOT:-"home"}

REMOTE_USER="ec2-user"  # default AWS user
REMOTE_HOST="$REMOTE_HOST"
REMOTE_KEY="/home/britivebroker/MYKEY.pem"  # <-- Path to your AWS PEM file


TRX=${TRX:-"britive-trx-id"}  # Transaction ID marker


# ==============================
# Generate SSH keypair in temp location
# ==============================
TMP_DIR=$(mktemp -d)
SSH_KEY_LOCAL="$TMP_DIR/britive-id_rsa"
SSH_KEY_PUB="$TMP_DIR/britive-id_rsa.pub"

ssh-keygen -q -N '' -t rsa -C "$USER_EMAIL" -f "$SSH_KEY_LOCAL"
#echo "✅ Generated new keypair (not stored permanently)"


# ==============================
# Create user and setup on remote server
# ==============================
ssh -i "$REMOTE_KEY" -o IdentitiesOnly=yes "$REMOTE_USER@$REMOTE_HOST" bash -s <<EOF
set -e

USER="$USER"
GROUP="$GROUP"
SUDO="$SUDO"
HOME_ROOT="$HOME_ROOT"
SSH_PATH=/${HOME_ROOT}/\${USER}/.ssh

if ! id -u "$USER" &>/dev/null; then
  useradd -m "$USER"
fi


if ! test -d "$SSH_PATH"; then
  mkdir -p "$SSH_PATH"
  chmod 700 "$SSH_PATH"
  chown "$USER:$GROUP" "$SSH_PATH"
fi


if [ "$SUDO" != "0" ]; then
  echo "${USER} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${USER}
  chmod 440 /etc/sudoers.d/${USER}
fi

EOF


# ==============================
# Append public key with TRX marker and push it to remote
# ==============================
PUB_KEY_WITH_MARKER="$(cat "$SSH_KEY_PUB") # britive-$TRX"

echo "$PUB_KEY_WITH_MARKER" > "$TMP_DIR/britive-id_rsa_marker.pub"

scp -i "$REMOTE_KEY" -o IdentitiesOnly=yes "$TMP_DIR/britive-id_rsa_marker.pub" "$REMOTE_USER@$REMOTE_HOST:/tmp/britive-id_rsa_marker.pub"

ssh -i "$REMOTE_KEY" -o IdentitiesOnly=yes "$REMOTE_USER@$REMOTE_HOST" bash -s <<EOF
set -e

USER="$USER"
HOME_ROOT="$HOME_ROOT"
SSH_PATH=/${HOME_ROOT}/\${USER}/.ssh

sudo bash -c "cat /tmp/britive-id_rsa_marker.pub >> \$SSH_PATH/authorized_keys"
sudo rm -f /tmp/britive-id_rsa_marker.pub
sudo chmod 600 "\$SSH_PATH/authorized_keys"
sudo chown "\$USER:\$USER" "\$SSH_PATH/authorized_keys"
EOF



SSH_KEY=$(cat "$SSH_KEY_LOCAL")

JSON_STRING='{
  "username": "'${USER_EMAIL}'",
  "expires": "'$(date -d "+${expiration} seconds" +%s)'000",
  "connections": {
    "'${connection_name}'":
      {
        "protocol": "ssh",
        "parameters": {
          "hostname": "'${hostname}'",
          "port": "'${port}'",
          "username": "'${USERNAME}'",
          "private-key": "'${SSH_KEY//$'\n'/\\n}'",
          "recording-path": "'${recording_path:-/home/guacd/recordings}'",
          "recording-name": "${GUAC_DATE}-${GUAC_TIME}-'${USER_EMAIL}'-'${USERNAME}'-'${connection_name}'"
        }
      }
  }
}'

JSON=$(echo -n $JSON_STRING|jq -r tostring)

sign() {
    echo -n "${JSON}" | openssl dgst -sha256 -mac HMAC -macopt hexkey:"${SECRET_KEY}" -binary
    echo -n "${JSON}"
}

encrypt() {
    openssl enc -aes-128-cbc -K "${SECRET_KEY}" -iv "00000000000000000000000000000000" -nosalt -a
}

TOKEN=$(sign | encrypt | tr -d "\n\r" | jq -Rr @uri)

echo -n '{"token": "'${TOKEN}'", "url": "'${url}'"}'


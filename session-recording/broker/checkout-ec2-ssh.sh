#!/bin/bash

USER_EMAIL=${BRITIVE_USER_EMAIL:-"test@example.com"}
USERNAME="${USER_EMAIL%%@*}"
USERNAME="${USERNAME//[^a-zA-Z0-9]/}"

USER=${USERNAME}
GROUP=${USERNAME}

SUDO=${BRITIVE_SUDO:-"0"}

useradd -m ${USER} 2>/dev/null

SSH_PATH=/${BRITIVE_HOME_ROOT:-"home"}/${USER}/.ssh

finish () {
  rm -f $SSH_PATH/britive-id_rsa*
  exit $1
}

if ! test -d $SSH_PATH; then
  mkdir -p $SSH_PATH || finish 1
  chmod 700 $SSH_PATH || finish 1
  chown $USER:$GROUP $SSH_PATH || finish 1
fi

ssh-keygen -q -N '' -t rsa -C $USER_EMAIL -f $SSH_PATH/britive-id_rsa || finish 1

mapfile -t contents < <(cat $SSH_PATH/authorized_keys 2>/dev/null | sort -u)
mapfile -t -O "${#contents[@]}" contents < <(cat $SSH_PATH/britive-id_rsa.pub 2>/dev/null)
printf "%s\n" "${contents[@]}" > $SSH_PATH/authorized_keys

chmod 600 $SSH_PATH/authorized_keys || finish 1
chown $USER:$GROUP $SSH_PATH/authorized_keys || finish 1


if [ "$SUDO" != "0" ]; then
  echo "${USER} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${USER} || finish 1
  chmod 440 /etc/sudoers.d/${USER} || finish 1
fi

SSH_KEY=$(cat $SSH_PATH/britive-id_rsa || finish 1)

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

REGION=$(ec2metadata --availability-zone)

SECRET_KEY=$(aws --region ${REGION::-1} secretsmanager get-secret-value --secret-id ${json_secret_key} --query "SecretString" | jq -r | jq -r .key)

sign() {
    echo -n "${JSON}" | openssl dgst -sha256 -mac HMAC -macopt hexkey:"${SECRET_KEY}" -binary
    echo -n "${JSON}"
}

encrypt() {
    openssl enc -aes-128-cbc -K "${SECRET_KEY}" -iv "00000000000000000000000000000000" -nosalt -a
}

TOKEN=$(sign | encrypt | tr -d "\n\r" | jq -Rr @uri)

echo -n '{"token": "'${TOKEN}'", "url": "'${url}'"}'

finish 0
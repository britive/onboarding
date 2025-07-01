#!/bin/bash

USER_EMAIL=${BRITIVE_USER_EMAIL:-"test@example.com"}
USERNAME="${USER_EMAIL%%@*}"
USERNAME="${USERNAME//[^a-zA-Z0-9\.]/}"

DOMAIN=${DOMAIN:-"ad.test.com"}

finish () {
  exit $1
}

JSON_STRING='{
  "username": "'${USER_EMAIL}'",
  "expires": "'$(date -d "+${expiration} seconds" +%s)'000",
  "connections": {
    "'${connection_name}'":
      {
        "protocol": "rdp",
        "parameters": {
          "hostname": "'${hostname}'",
          "port": "'${port}'",
          "security": "'${security:-nla}'",
          "ignore-cert": "'${ignore_cert:-true}'",
          "username": "'${USERNAME}'",
          "domain": "'${DOMAIN}'",
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

finish 0
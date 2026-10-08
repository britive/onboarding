#!/bin/bash
# Signs and encrypts a Guacamole JSON auth object (guacamole-auth-json) and
# prints {"token": "<url-encoded token>"} for use as ?data=<token>.
#
# Usage: ./encrypt-token.sh <json-secret-key> <json-file>
#   json-secret-key  128-bit AES key as 32 hex characters: openssl rand -hex 16
#   json-file        see example_user.json
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 <json-secret-key> <json-file>" >&2
  exit 1
fi

JSON_SECRET_KEY=$1
JSON_FILE=$2

if ! [[ "$JSON_SECRET_KEY" =~ ^[0-9A-Fa-f]{32}$ ]]; then
  echo "ERROR: json-secret-key must be 32 hex characters (openssl rand -hex 16)" >&2
  exit 1
fi

JSON=$(jq -c . "$JSON_FILE")

sign() {
  echo -n "${JSON}" | openssl dgst -sha256 -mac HMAC -macopt hexkey:"${JSON_SECRET_KEY}" -binary
  echo -n "${JSON}"
}

encrypt() {
  openssl enc -aes-128-cbc -K "${JSON_SECRET_KEY}" -iv "00000000000000000000000000000000" -nosalt -a
}

TOKEN=$(sign | encrypt | tr -d "\n\r" | jq -Rr @uri)

jq -cn --arg token "$TOKEN" '{token: $token}'

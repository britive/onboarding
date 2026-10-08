#!/bin/bash
# Started by supervisord. Runs whichever britive-broker-*.jar was copied into
# /root/broker at build time, so the version only lives in the Dockerfile ARG.
set -u

sleep "${1:-0}"

BROKER_DIR=/root/broker

shopt -s nullglob
jars=("$BROKER_DIR"/britive-broker-*.jar)
shopt -u nullglob

if [[ ${#jars[@]} -eq 0 ]]; then
  echo "ERROR: no britive-broker-*.jar found in $BROKER_DIR" >&2
  exit 1
fi
if [[ ${#jars[@]} -gt 1 ]]; then
  echo "ERROR: more than one broker JAR in $BROKER_DIR: ${jars[*]}" >&2
  exit 1
fi

cd "$BROKER_DIR" || exit 1
echo "Starting ${jars[0]}"
exec /usr/bin/java -jar "${jars[0]}"

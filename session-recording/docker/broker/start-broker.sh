#!/bin/bash
sleep "$1"

_term() {
  echo "Caught SIGTERM signal!"
  kill -TERM "$child" 2>/dev/null
}

trap _term SIGTERM
trap _term SIGINT

/usr/bin/python3 /root/create-resources.py
cd /root/broker && /usr/bin/java -Djavax.net.debug=all -jar britive-broker-1.0.0.jar &

child=$!
wait "$child"


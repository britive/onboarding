#!/bin/bash

# Token generator for ECS Fargate — reads from secrets file (preferred) or env var fallback.
# The broker calls this script to obtain the Britive authentication token.

SECRET_FILE="/root/broker/secrets/BRITIVE_TOKEN"

if [ -f "$SECRET_FILE" ]; then
    cat "$SECRET_FILE"
else
    echo "$BRITIVE_TOKEN"
fi

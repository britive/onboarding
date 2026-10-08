#!/usr/bin/env bash
#
# DBeaver "Password from Shell Command": DBeaver runs this on every connect
# and uses the first line of stdout as the password. Nothing is written to
# disk.
#
# Usage (set as the command in DBeaver, see dbeaver.md):
#   /path/to/dbeaver-password.sh <pybritive profile or alias> [json-key]
#
# The profile's response template decides the JSON keys of the checkout
# output; "password" is the common choice. Database profiles brokered by the
# Access Broker are "my-resources" profiles.

set -euo pipefail

PROFILE="${1:?pybritive profile or alias}"
KEY="${2:-password}"

# DBeaver's environment usually lacks your shell PATH; name the binaries.
PYBRITIVE="${PYBRITIVE:-$(command -v pybritive || echo /usr/local/bin/pybritive)}"
JQ="${JQ:-$(command -v jq || echo /usr/local/bin/jq)}"

exec "$PYBRITIVE" checkout "$PROFILE" --silent --mode json --profile-type my-resources \
  | "$JQ" -r --arg k "$KEY" '.[$k] // error("key \($k) not in checkout output")'

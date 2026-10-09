#!/usr/bin/env bash
#
# generate-parameters.sh - write a CloudFormation parameters file for
# britive_integration_resources.yaml with the SAML metadata correctly
# JSON-escaped (the part people get wrong by hand).
#
# Usage:
#   ./generate-parameters.sh <tenant-name> <saml-metadata.xml> [options]
#
# Options:
#   --no-invalidation      DeployAwsInvalidationFeature=false (default true)
#   --access-builder       DeployAccessBuilder=true
#   --ai-scanning          DeployAiIdentityScanning=true
#   --sample-roles         DeploySampleRoles=true
#   --max-session <sec>    MaxSessionDuration (default 3600)
#   --identity-center      DeployIdentityCenter=true (management account only)
#   --account-access <arn> DeployAccountAccess=true with the account access
#                          manager application ARN (arn:aws:account-access:...)
#   -o, --output <file>    where to write (default ./parameters.json, gitignored)
#
# The same file works for a single-account stack and for a StackSet (do not
# use the Identity Center or Account Access options for a member-account
# StackSet). For the organization wrapper, add its S3 and OU parameters by
# hand.

set -euo pipefail

usage() {
  sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'
  exit 1
}

command -v jq >/dev/null 2>&1 || { echo "jq is required (brew install jq / apt-get install jq)" >&2; exit 1; }

TENANT_NAME="${1:-}"
SAML_FILE="${2:-}"
[ -n "$TENANT_NAME" ] && [ -n "$SAML_FILE" ] || usage
shift 2

INVALIDATION=true
ACCESS_BUILDER=false
AI_SCANNING=false
SAMPLE_ROLES=false
MAX_SESSION=3600
IDENTITY_CENTER=false
ACCOUNT_ACCESS=false
ACCOUNT_ACCESS_ARN=""
OUTPUT=parameters.json

while [ $# -gt 0 ]; do
  case "$1" in
    --no-invalidation) INVALIDATION=false ;;
    --access-builder)  ACCESS_BUILDER=true ;;
    --ai-scanning)     AI_SCANNING=true ;;
    --sample-roles)    SAMPLE_ROLES=true ;;
    --max-session)     MAX_SESSION="${2:?seconds}"; shift ;;
    --identity-center) IDENTITY_CENTER=true ;;
    --account-access)  ACCOUNT_ACCESS=true; ACCOUNT_ACCESS_ARN="${2:?application ARN}"; shift ;;
    -o|--output)       OUTPUT="${2:?file}"; shift ;;
    -h|--help)         usage ;;
    *) echo "unknown option: $1" >&2; usage ;;
  esac
  shift
done

if [ "$ACCOUNT_ACCESS" = true ] && [[ ! "$ACCOUNT_ACCESS_ARN" =~ ^arn:aws[a-z-]*:account-access:[a-z0-9-]+:[0-9]{12}:application/ ]]; then
  echo "--account-access needs the ARN from the account access manager Settings page (arn:aws:account-access:<region>:<account>:application/...), not the arn:aws:sso:: one" >&2
  exit 1
fi

[[ "$TENANT_NAME" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]*$ ]] || { echo "tenant name must be the subdomain only, e.g. acme" >&2; exit 1; }
[ -f "$SAML_FILE" ] || { echo "SAML metadata file not found: $SAML_FILE" >&2; exit 1; }
grep -q EntityDescriptor "$SAML_FILE" || { echo "$SAML_FILE does not look like SAML metadata (no EntityDescriptor)" >&2; exit 1; }
if command -v xmllint >/dev/null 2>&1; then
  xmllint --noout "$SAML_FILE" || { echo "$SAML_FILE is not well-formed XML" >&2; exit 1; }
fi

jq -n \
  --arg tenant "$TENANT_NAME" \
  --rawfile saml "$SAML_FILE" \
  --arg inv "$INVALIDATION" \
  --arg ab "$ACCESS_BUILDER" \
  --arg ai "$AI_SCANNING" \
  --arg roles "$SAMPLE_ROLES" \
  --arg msd "$MAX_SESSION" \
  --arg ic "$IDENTITY_CENTER" \
  --arg aa "$ACCOUNT_ACCESS" \
  --arg aaarn "$ACCOUNT_ACCESS_ARN" \
  '[
    {ParameterKey: "TenantName", ParameterValue: $tenant},
    {ParameterKey: "SamlMetadataDocumentXmlContent", ParameterValue: $saml},
    {ParameterKey: "DeployAwsInvalidationFeature", ParameterValue: $inv},
    {ParameterKey: "DeployAccessBuilder", ParameterValue: $ab},
    {ParameterKey: "DeployAiIdentityScanning", ParameterValue: $ai},
    {ParameterKey: "DeploySampleRoles", ParameterValue: $roles},
    {ParameterKey: "MaxSessionDuration", ParameterValue: $msd},
    {ParameterKey: "DeployIdentityCenter", ParameterValue: $ic},
    {ParameterKey: "DeployAccountAccess", ParameterValue: $aa},
    {ParameterKey: "AccountAccessApplicationArn", ParameterValue: $aaarn}
  ]' > "$OUTPUT"

echo "wrote $OUTPUT (tenant=$TENANT_NAME invalidation=$INVALIDATION access-builder=$ACCESS_BUILDER ai-scanning=$AI_SCANNING sample-roles=$SAMPLE_ROLES max-session=$MAX_SESSION identity-center=$IDENTITY_CENTER account-access=$ACCOUNT_ACCESS)" >&2

#!/bin/bash

# Britive CloudFormation Parameter Generator
# This script generates a parameters.json file for CloudFormation deployment
# with properly escaped SAML metadata content.

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Usage function
usage() {
  echo "Usage: $0 <tenant-name> <saml-metadata-file> [enable-invalidation]"
  echo ""
  echo "Arguments:"
  echo "  tenant-name           Your Britive tenant name (e.g., 'mycompany' for mycompany.britive-app.com)"
  echo "  saml-metadata-file    Path to the SAML metadata XML file downloaded from Britive"
  echo "  enable-invalidation   Optional: 'true' or 'false' (default: true)"
  echo ""
  echo "Example:"
  echo "  $0 mycompany britive-saml-metadata.xml true"
  echo ""
  exit 1
}

# Check if jq is installed
if ! command -v jq &> /dev/null; then
  echo -e "${RED}Error: 'jq' is required but not installed.${NC}"
  echo "Install it using:"
  echo "  macOS:   brew install jq"
  echo "  Ubuntu:  sudo apt-get install jq"
  echo "  RHEL:    sudo yum install jq"
  exit 1
fi

# Parse arguments
TENANT_NAME=${1}
SAML_FILE=${2}
ENABLE_INVALIDATION=${3:-true}

# Validate arguments
if [ -z "$TENANT_NAME" ] || [ -z "$SAML_FILE" ]; then
  usage
fi

# Validate invalidation parameter
if [[ "$ENABLE_INVALIDATION" != "true" && "$ENABLE_INVALIDATION" != "false" ]]; then
  echo -e "${RED}Error: enable-invalidation must be 'true' or 'false'${NC}"
  exit 1
fi

# Check if SAML file exists
if [ ! -f "$SAML_FILE" ]; then
  echo -e "${RED}Error: SAML metadata file not found: $SAML_FILE${NC}"
  exit 1
fi

# Validate SAML file is valid XML
if ! xmllint --noout "$SAML_FILE" 2>/dev/null; then
  echo -e "${YELLOW}Warning: Unable to validate XML (xmllint not installed or XML is malformed)${NC}"
  echo -e "${YELLOW}Continuing anyway...${NC}"
fi

echo "Generating CloudFormation parameters file..."
echo ""

# Read and properly escape SAML content for JSON
SAML_CONTENT=$(cat "$SAML_FILE" | jq -Rs .)

# Generate parameters.json
cat > parameters.json << EOF
[
  {
    "ParameterKey": "TenantName",
    "ParameterValue": "${TENANT_NAME}"
  },
  {
    "ParameterKey": "SamlMetadataDocumentXmlContent",
    "ParameterValue": ${SAML_CONTENT}
  },
  {
    "ParameterKey": "DeployAwsInvalidationFeature",
    "ParameterValue": "${ENABLE_INVALIDATION}"
  }
]
EOF

# Validate generated JSON
if ! jq empty parameters.json 2>/dev/null; then
  echo -e "${RED}Error: Generated parameters.json is not valid JSON${NC}"
  exit 1
fi

# Success message
echo -e "${GREEN}✓ Successfully generated parameters.json${NC}"
echo ""
echo "Configuration:"
echo "  • Tenant Name:        ${TENANT_NAME}"
echo "  • SAML Metadata:      ${SAML_FILE}"
echo "  • AWS Invalidation:   ${ENABLE_INVALIDATION}"
echo ""
echo "Next steps:"
echo "  1. Review the generated parameters.json file"
echo "  2. Deploy using AWS CLI:"
echo ""
echo "     For StackSets:"
echo "     aws cloudformation create-stack-set \\"
echo "       --stack-set-name britive-integration \\"
echo "       --template-body file://britive_integration_resources_stackset.yaml \\"
echo "       --parameters file://parameters.json \\"
echo "       --permission-model SERVICE_MANAGED \\"
echo "       --capabilities CAPABILITY_NAMED_IAM"
echo ""
echo "     For Single Account:"
echo "     aws cloudformation create-stack \\"
echo "       --stack-name britive-integration \\"
echo "       --template-body file://britive_integration_resources.yaml \\"
echo "       --parameters file://parameters.json \\"
echo "       --capabilities CAPABILITY_NAMED_IAM"
echo ""

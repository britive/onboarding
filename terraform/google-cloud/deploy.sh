#!/usr/bin/env bash
# Deploy the Britive Google Cloud integration, end to end:
#   1. Google Cloud: project, APIs, Britive role and service account, and either a
#      workload identity pool (wif) or a service account key (key)      -> this directory
#   2. Key mode only: Google Workspace admin role and user, after you grant
#      domain-wide delegation by hand                                   -> ../google-workspace
#   3. The Britive application, when BRITIVE_TENANT and BRITIVE_TOKEN are set
#                                                                       -> britive-app/
# Run from anywhere: ./deploy.sh. Needs terraform, gcloud and jq, and
# terraform.tfvars in this directory (copy terraform.tfvars.example).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE_DIR="$HERE/../google-workspace"
APP_DIR="$HERE/britive-app"

fail() { echo "error: $*" >&2; exit 1; }
for tool in terraform gcloud jq; do
  command -v "$tool" >/dev/null || fail "$tool is not installed"
done
[ -f "$HERE/terraform.tfvars" ] || fail "copy terraform.tfvars.example to terraform.tfvars in $HERE and fill it in"

# Terraform uses Application Default Credentials; sign in only if they are missing.
if ! gcloud auth application-default print-access-token >/dev/null 2>&1; then
  gcloud auth application-default login
fi

echo "== 1/3 Google Cloud"
terraform -chdir="$HERE" init -input=false
terraform -chdir="$HERE" apply
mode=$(terraform -chdir="$HERE" output -raw integration_type)

if [ "$mode" = "key" ]; then
  echo
  echo "== 2/3 Google Workspace (key mode)"
  [ -f "$WORKSPACE_DIR/terraform.tfvars" ] \
    || fail "copy terraform.tfvars.example to terraform.tfvars in $WORKSPACE_DIR and fill it in"
  client_id=$(terraform -chdir="$HERE" output -raw service_account_client_id)
  cat <<EOF
Grant domain-wide delegation to the Britive service account, as a Workspace super administrator:
  https://admin.google.com/ac/owl/domainwidedelegation
  Add new -> Client ID: $client_id
  OAuth scopes:
    https://www.googleapis.com/auth/admin.directory.user,https://www.googleapis.com/auth/cloud-platform,https://www.googleapis.com/auth/admin.directory.group,https://www.googleapis.com/auth/admin.directory.group.member,https://www.googleapis.com/auth/admin.directory.rolemanagement
EOF
  read -rp "Press ENTER once delegation is saved..."

  terraform -chdir="$WORKSPACE_DIR" init -input=false
  # The plan file holds the generated password; remove it however this exits.
  trap 'rm -f "$WORKSPACE_DIR/tfplan"' EXIT
  # Delegation takes a few minutes to take effect; until then the plan fails with
  # unauthorized_client. Retry only that error, for up to 10 minutes.
  for attempt in $(seq 1 30); do
    if terraform -chdir="$WORKSPACE_DIR" plan -input=false -out=tfplan 2> "$WORKSPACE_DIR/plan.err"; then
      rm -f "$WORKSPACE_DIR/plan.err"
      break
    fi
    if ! grep -q unauthorized_client "$WORKSPACE_DIR/plan.err"; then
      cat "$WORKSPACE_DIR/plan.err" >&2
      rm -f "$WORKSPACE_DIR/plan.err"
      fail "the Workspace plan failed for a reason other than pending delegation (see above)"
    fi
    [ "$attempt" -lt 30 ] || fail "Workspace still refuses the service account after 10 minutes: check the client ID and scopes above"
    echo "waiting for domain-wide delegation to take effect (attempt $attempt/30)..."
    sleep 20
  done
  read -rp "Apply this plan? [y/N] " answer
  [ "$answer" = "y" ] || [ "$answer" = "Y" ] || fail "stopped before applying the Workspace plan"
  terraform -chdir="$WORKSPACE_DIR" apply -input=false tfplan
  rm -f "$WORKSPACE_DIR/tfplan"
fi

echo
echo "== 3/3 Britive application"
if [ -n "${BRITIVE_TENANT:-}" ] && [ -n "${BRITIVE_TOKEN:-}" ]; then
  terraform -chdir="$APP_DIR" init -input=false
  terraform -chdir="$APP_DIR" apply
  terraform -chdir="$APP_DIR" output -raw next_step; echo
else
  echo "BRITIVE_TENANT and BRITIVE_TOKEN are not set: create the application in the Britive console"
  echo "(Applications -> Add Application -> $( [ "$mode" = "wif" ] && echo "Google Cloud Platform WIF" || echo "Google Cloud Platform" ))"
  echo "with these values, or set both variables and run this script again:"
  terraform -chdir="$HERE" output -json britive_application_values | jq .
  [ "$mode" = "key" ] && terraform -chdir="$WORKSPACE_DIR" output
fi
if [ "$mode" = "key" ]; then
  echo
  echo "The service account key is $HERE/keys/key.json (mode 0600, git-ignored). Upload it to the"
  echo "Britive application, then keep it out of shared folders and chat. It is also in terraform.tfstate."
fi

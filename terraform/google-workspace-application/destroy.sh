#!/usr/bin/env bash
# Remove the Britive Google Workspace integration, in the reverse order of
# deploy.sh: the Britive application, the Workspace role and user, then the
# Google Cloud resources. Each step runs only if that root has state.
#
# The project is protected by default. To delete it as well, set
# allow_project_deletion = true in terraform.tfvars and run `terraform apply`
# once before this script. Otherwise remove it from state first:
#   terraform state rm 'google_project.britive[0]'
#
# ../google-workspace needs the rolemanagement delegation scope to delete the
# admin role; re-add it in the Admin console if you removed it.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"

export TF_VAR_service_account_key_file="$HERE/keys/key.json"
for dir in "$HERE/britive-app" "$HERE/../google-workspace" "$HERE"; do
  if [ -f "$dir/terraform.tfstate" ]; then
    echo "== destroying $(basename "$dir")"
    terraform -chdir="$dir" init -input=false >/dev/null
    terraform -chdir="$dir" destroy
  fi
done

rm -f "$HERE/keys/key.json"

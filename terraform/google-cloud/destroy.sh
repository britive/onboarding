#!/usr/bin/env bash
# Remove the Britive Google Cloud integration, in the reverse order of deploy.sh:
# the Britive application, the Google Workspace role and user (key mode), then the
# Google Cloud resources. Each step runs only if that root has state.
#
# The project is protected by default. To delete it as well, set
# allow_project_deletion = true in terraform.tfvars and run `terraform apply` once
# before this script. Otherwise remove it from state first:
#   terraform state rm 'google_project.britive[0]'
#
# Deleted IDs stay reserved: the custom role ID for several weeks and the workload
# identity pool ID for 30 days. Re-creating the integration soon after needs new
# role_id and workload_identity_pool_id values.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"

for dir in "$HERE/britive-app" "$HERE/../google-workspace" "$HERE"; do
  if [ -f "$dir/terraform.tfstate" ]; then
    echo "== destroying $(basename "$dir")"
    terraform -chdir="$dir" init -input=false >/dev/null
    terraform -chdir="$dir" destroy
  fi
done

rm -f "$HERE/keys/key.json"

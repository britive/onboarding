#!/bin/bash

gcloud auth application-default login

clear

cd gcp
terraform init
terraform apply -var-file=../variables.tfvars
terraform output > ../outputs/gcp.txt

clear

cd ..

clientid=$(cat ./keys/key.json | jq -r '.client_id')
echo "now manually do domain-wide delegation..."
echo "admin.google.com > login > Security > Access and data control > API controls > Manage Domain Wide Delegation"
echo "or"
echo "direct link: https://admin.google.com/ac/owl/domainwidedelegation?hl=en"
echo ""
echo "Add new..."
echo "client id: $clientid"
echo "oauth scopes: https://www.googleapis.com/auth/admin.directory.user,https://www.googleapis.com/auth/cloud-platform,https://www.googleapis.com/auth/admin.directory.group,https://www.googleapis.com/auth/admin.directory.group.member,https://www.googleapis.com/auth/admin.directory.rolemanagement"
echo ""
read -p "Press ENTER to continue (once the above actions are completed)..."

cd workspace

clear
terraform init
clear

while ! terraform apply -var-file=../variables.tfvars
do
    clear
    echo waiting for domain wide delegation action to complete - sleeping 10 seconds
    sleep 10
done

terraform output > ../outputs/workspace.txt

cd ..

clear

echo "required data points to create Britive GCP application..."
echo ""
cat outputs/gcp.txt
cat outputs/workspace.txt
echo ""
echo "below is the service account credentials (content of private key file as JSON string)"
cat keys/key.json







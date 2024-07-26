cd workspace
clear
terraform destroy -var-file=../variables.tfvars
clear
cd ../gcp
terraform destroy -var-file=../variables.tfvars

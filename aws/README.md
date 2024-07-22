# Britive - AWS Onboarding

We offer AWS templates in various formats.

* CloudFormation
* Terraform (tbd)
* Python (tbd)
* CLI (tbd)

Choose the subdirectory for the method you wish to use to deploy the requried AWS resources to setup the
integration with Britive.

Note that only CloudFormation offers single deployment option which will deploy the required resources to 
all AWS accounts in your AWS Organization, via CloudFormation Stacksets.



Directory Structure

📦aws
 ┣ 📂cloudformation
 ┃ ┣ 📂organization-stackset
 ┃ ┃ ┣ 📜README.md
 ┃ ┃ ┣ 📜britive_integration_resources.yaml
 ┃ ┃ ┣ 📜deploy_britive_integration_resources.yaml
 ┃ ┃ ┗ 📜parameters.json
 ┃ ┣ 📂single-account-stack
 ┃ ┃ ┣ 📜README.md
 ┃ ┃ ┣ 📜britive_integration_resources.yaml
 ┃ ┃ ┗ 📜parameters.json
 ┃ ┗ 📜README.md
 ┣ 📂python
 ┣ 📂terraform
 ┗ 📜README.md
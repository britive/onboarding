# Snowflake Terraform example

This Terraform project automates the creation of a custom Snowflake role and user for Britive integration.

## Features

- Creates a custom role (`BRITIVEROLE`) with necessary privileges.
- Grants `ORGADMIN` to the custom role.
- Creates a user (`BRITIVEUSER`) and assigns it the custom role.
- Supports key-pair authentication.
- Uses Terraform variables for easy customization.

## Prerequisites

- Terraform installed ([Download Terraform](https://developer.hashicorp.com/terraform/downloads)).
- Snowflake account credentials.
- A public/private key pair for authentication.

## Setup

### 1. Clone the Repository

```sh
git clone <repository-url>
cd <repository-folder>
```

### 2. Update the Terraform Variables

Edit `variables.tfvars` to set your Snowflake account details:

```hcl
snowflake_account       = "your_snowflake_account"
snowflake_user          = "your_snowflake_user"
snowflake_password      = "your_snowflake_password"
britive_public_key_path = "./britive_public_key.pem"
```

### 3. Initialize Terraform

```sh
terraform init
```

### 4. Plan the Deployment

```sh
terraform plan -var-file=variables.tfvars
```

### 5. Apply the Configuration

```sh
terraform apply -var-file=variables.tfvars -auto-approve
```

## Outputs

- The configured public key file path (`britive_public_key.pem`).

## Cleanup

To remove all created resources:

```sh
terraform destroy -var-file=variables.tfvars -auto-approve
```

## Notes

- The private key should be securely stored and never committed to version control.
- Ensure you have `ACCOUNTADMIN` or equivalent privileges when running Terraform.

## Troubleshooting

If you encounter errors:

- Verify your Snowflake credentials and role permissions.
- Ensure Terraform is properly installed.
- Check the Snowflake provider documentation for updates: [Snowflake Terraform Provider](https://registry.terraform.io/providers/Snowflake-Labs/snowflake/latest/docs).

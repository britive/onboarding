# Britive AWS Integration Script

This Python script integrates Britive as an identity provider (IdP) in AWS, and also creates an IAM role with SAML-based federation for Britive-managed roles.

## Features

- **Create SAML Identity Provider in AWS**: Automatically provisions Britive as an IdP in AWS using the SAML metadata.
- **Create IAM Role for SAML-based Federation**: Sets up an IAM role with the required trust policies and inline policies for Britive integration.
- **Session Invalidation Support**: Optional session invalidation configuration for added security when creating the role.

## Requirements

- Python 3.x
- AWS credentials configured (through environment variables or AWS CLI).
- The following environment variables must be set:
  - `AWS_ACCOUNT`: Your AWS account ID.
  - `BRITIVE_TENANT`: Britive tenant name.
  - `BRITIVE_API_TOKEN`: Britive API token for authentication.

### Python Dependencies

Make sure to install the required Python packages using `pip`:

```bash
pip3 install -r requirements.txt

# Set the right AWS Profile for boto3. 
export AWS_PROFILE=demo
```

# Usage

usage: setup_aws.py [-h] [-i] [-r] [-s]

Process some command-line arguments.

optional arguments:
  -h, --help        Show this help message and exit.
  -i, --idp         Create Britive as an Identity Provider
  -r, --role        Create Britive Integration Role
  -s, --session     Setup for session invalidation
  -m, --managed     Setup for Britive managed profiles and Access Builder

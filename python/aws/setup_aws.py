#!/usr/bin/env python3
import argparse
import boto3
import os
from colored import Fore, Style
from britive.britive import Britive

try:
    import simplejson as json
except ImportError:
    import json

# Color definitions
caution: str = f'{Style.BOLD}{Fore.red}'
warn: str = f'{Style.BOLD}{Fore.yellow}'
info: str = f'{Style.BOLD}{Fore.blue}'
green: str = f'{Style.BOLD}{Fore.green}'

# Initialize the IAM client
client = boto3.client('iam')
br = Britive(tenant=os.getenv("BRITIVE_TENANT"), token=os.getenv("BRITIVE_API_TOKEN"))
saml_provider_arn = ''


def create_idp():
    # SAML metadata document, you can load it from a file or provide directly as a string.
    # Make sure it is the SAML Metadata document from your Identity Provider.
    saml_metadata_document = br.saml.metadata()

    # Name for your identity provider
    identity_provider_name = "Britive"

    try:
        # Create the SAML Identity Provider
        response = client.create_saml_provider(
            SAMLMetadataDocument=saml_metadata_document,
            Name=identity_provider_name
        )
        saml_provider_arn = response['SAMLProviderArn']
        # Print the response from AWS (containing the ARN of the new provider)
        print(f"{info}Identity Provider ARN: {saml_provider_arn}{Style.reset}")
    except Exception as e:
        print(f"{caution}Error creating Identity Provider: {e}{Style.reset}")


def create_role(sess):
    aws_account_id = ''
    # SAML Provider ARN (replace this with your actual SAML provider ARN)
    saml_provider_arn = 'arn:aws:iam::' + aws_account_id + '<account_id>:saml-provider/Britive'

    # Role name and description
    role_name = 'britive-integration-role'
    role_description = 'Role for federated access using SAML and Britive-managed support'

    # Trust policy for SAML-based role creation
    trust_policy = {
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Principal": {
                    "Federated": saml_provider_arn
                },
                "Action": ["sts:AssumeRoleWithSAML",
                           "sts:SetSourceIdentity"
                           ],
                "Condition": {
                    "StringEquals": {
                        "SAML:aud": "https://signin.aws.amazon.com/saml"
                    }
                }
            }
        ]
    }

    # Inline policy for Britive-managed roles support
    inline_policy = {
        "Version": "2012-10-17",
        "Statement": [
            {
                "Sid": "VisualEditor0",
                "Effect": "Allow",
                "Action": [
                    "iam:DetachRolePolicy",
                    "iam:UntagRole",
                    "iam:DeleteRolePolicy",
                    "iam:TagRole",
                    "iam:CreateRole",
                    "iam:DeleteRole",
                    "iam:AttachRolePolicy",
                    "iam:UpdateRole",
                    "iam:PutRolePolicy"
                ],
                "Resource": "arn:aws:iam::*:policy/britive/managed/*"
            }
        ]
    }
    if sess:
        inv_actions = [
            "iam:CreatePolicy",
            "iam:DeletePolicy",
            "iam:CreatePolicyVersion",
            "iam:DeletePolicyVersion",
            "iam:GetPolicy",
            "iam:GetPolicyVersion",
            "iam:ListPolicyVersions"
        ]
        # Update policy to include session invalidation
        inline_policy["Statement"][0]["Action"].extend(inv_actions)
        inv_trust = ["sts:TagSession"]
        trust_policy["Statement"][0]["Action"].extend(inv_trust)

    # Create the IAM Role
    try:
        create_role_response = client.create_role(
            RoleName=role_name,
            AssumeRolePolicyDocument=json.dumps(trust_policy),
            Description=role_description,
            MaxSessionDuration=3600  # Set max session duration to 1 hour
        )
        print(f"{info}Role created successfully: {create_role_response['Role']['Arn']}{Style.reset}")
    except Exception as e:
        print(f"{caution}Error creating role: {e}{Style.reset}")
        exit(1)

    # Attach the necessary managed policies
    try:
        client.attach_role_policy(
            RoleName=role_name,
            PolicyArn='arn:aws:iam::aws:policy/IAMReadOnlyAccess'
        )
        client.attach_role_policy(
            RoleName=role_name,
            PolicyArn='arn:aws:iam::aws:policy/AWSOrganizationsReadOnlyAccess'
        )
        print(f'{info}Attached IAMReadOnlyAccess and AWSOrganizationsReadOnlyAccess policies.{Style.reset}')
    except Exception as e:
        print(f'{caution}Error attaching policies: {e}{Style.reset}')
        exit(1)

    # Add the inline policy for Britive-managed roles support
    try:
        client.put_role_policy(
            RoleName=role_name,
            PolicyName='BritiveManagedRolesSupport',
            PolicyDocument=json.dumps(inline_policy)
        )
        print(f'{info}Added inline policy for Britive-managed roles support.{Style.reset}')
    except Exception as e:
        print(f'Error adding inline policy: {e}{Style.reset}')
        exit(1)

    print(f'{info}Role {role_name} setup complete.{Style.reset}')


def main():
    parser = argparse.ArgumentParser(description='Process some command-line arguments.')
    parser.add_argument('-i', '--idp', action='store_true', help='Create Britive as an Identity Provider')
    parser.add_argument('-r', '--role', action='store_true', help='Create Britive Integration Role')
    parser.add_argument('-s', '--session', action='store_true', help='Setup for session invalidation')
    args = parser.parse_args()
    if args.idp:
        create_idp()
    if args.role:
        create_role(args.session)


if __name__ == '__main__':
    main()

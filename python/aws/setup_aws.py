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

# Initialize the IAM client




class BritiveInt:
    def __init__(self):
        # Color definitions
        self.caution: str = f'{Style.BOLD}{Fore.red}'
        self.warn: str = f'{Style.BOLD}{Fore.yellow}'
        self.info: str = f'{Style.BOLD}{Fore.blue}'
        self.green: str = f'{Style.BOLD}{Fore.green}'
        self.saml_provider_arn = ''
        self.saml_metadata_document = ''
        self.iam_client = boto3.client('iam')
        self.br = Britive(tenant=os.getenv("BRITIVE_TENANT"), token=os.getenv("BRITIVE_API_TOKEN"))

    def create_idp(self):
        # SAML metadata document, you can load it from a file or provide directly as a string.
        # Make sure it is the SAML Metadata document from your Identity Provider.
        self.saml_provider_arn = self.br.saml.metadata()
        self.saml_metadata_document = self.br.saml.metadata()

        # Name for your identity provider
        identity_provider_name = "Britive"

        try:
            # Create the SAML Identity Provider
            response = self.iam_client.create_saml_provider(
                SAMLMetadataDocument=self.saml_metadata_document,
                Name=identity_provider_name
            )
            saml_provider_arn = response['SAMLProviderArn']
            # Print the response from AWS (containing the ARN of the new provider)
            print(f"{self.info}Identity Provider ARN: {saml_provider_arn}{Style.reset}")
        except Exception as e:
            print(f"{self.caution}Error creating Identity Provider: {e}{Style.reset}")

    def create_role(self, sess):
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
            create_role_response = self.iam_client.create_role(
                RoleName=role_name,
                AssumeRolePolicyDocument=json.dumps(trust_policy),
                Description=role_description,
                MaxSessionDuration=3600  # Set max session duration to 1 hour
            )
            print(f"{self.info}Role created successfully: {create_role_response['Role']['Arn']}{Style.reset}")
        except Exception as e:
            print(f"{self.caution}Error creating role: {e}{Style.reset}")
            exit(1)

        # Attach the necessary managed policies
        try:
            self.iam_client.attach_role_policy(
                RoleName=role_name,
                PolicyArn='arn:aws:iam::aws:policy/IAMReadOnlyAccess'
            )
            self.iam_client.attach_role_policy(
                RoleName=role_name,
                PolicyArn='arn:aws:iam::aws:policy/AWSOrganizationsReadOnlyAccess'
            )
            print(f'{self.info}Attached IAMReadOnlyAccess and AWSOrganizationsReadOnlyAccess policies.{Style.reset}')
        except Exception as e:
            print(f'{self.caution}Error attaching policies: {e}{Style.reset}')
            exit(1)

        # Add the inline policy for Britive-managed roles support
        try:
            self.iam_client.put_role_policy(
                RoleName=role_name,
                PolicyName='BritiveManagedRolesSupport',
                PolicyDocument=json.dumps(inline_policy)
            )
            print(f'{self.info}Added inline policy for Britive-managed roles support.{Style.reset}')
        except Exception as e:
            print(f'Error adding inline policy: {e}{Style.reset}')
            exit(1)

        print(f'{self.info}Role {role_name} setup complete.{Style.reset}')


if __name__ == "__main__":
    # Instantiate the class
    br_int = BritiveInt()
    parser = argparse.ArgumentParser(description='Process some command-line arguments.')
    parser.add_argument('-i', '--idp', action='store_true', help='Create Britive as an Identity Provider')
    parser.add_argument('-r', '--role', action='store_true', help='Create Britive Integration Role')
    parser.add_argument('-s', '--session', action='store_true', help='Setup for session invalidation')
    args = parser.parse_args()
    if args.idp:
        BritiveInt.create_idp()
    if args.role:
        BritiveInt.create_role(args.session)

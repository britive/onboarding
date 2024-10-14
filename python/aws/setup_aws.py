#!/usr/bin/env python3
import argparse
import boto3
import os
from dotenv import load_dotenv
import json
from colorama import Fore, Style
from britive.britive import Britive


class BritiveInt:
    def __init__(self, sess: bool = False, managed: bool = False):
        # Color definitions from Colorama
        self.caution: str = f'{Style.BRIGHT}{Fore.RED}'
        self.warn: str = f'{Style.BRIGHT}{Fore.YELLOW}'
        self.info: str = f'{Style.BRIGHT}{Fore.BLUE}'
        self.green: str = f'{Style.BRIGHT}{Fore.GREEN}'

        # SAML Provider once created in AWS would have unique ARN to be stored for future use
        # SAML metadata document would be Britive idp metadata in xml format
        self.saml_provider_arn = ''
        self.saml_metadata_document = ''

        '''
        Fetch variables from .env file. 
        Make sure .env file locally exists with the following attributes
        AWS_ACCOUNT : The AWS Account ID (number)
        BRITIVE_TENANT : Britive Tenant URL. 'acme' or 'acme.britive-app.com'
        BRITIVE_API_TOKEN : BRITIVE Service Principal Token with Tenant admin privileges
        '''
        env_path = os.path.join('aws', '.env')
        load_dotenv(dotenv_path=env_path)
        self.aws_account_id = os.getenv("AWS_ACCOUNT")
        self.britive_tenant = os.getenv("BRITIVE_TENANT")
        self.britive_api_token = os.getenv("BRITIVE_API_TOKEN")

        # Define Identity Provider name to be created in AWS
        self.identity_provider_name = "Britive4"

        # Role name and description
        self.role_name = 'britive-integration-role4'
        self.role_description = 'Role for federated access using SAML and Britive-managed support'

        # Session Invalidation and Britive managed policies flag
        self.sess = sess
        self.managed = managed

        # Initialize AWS IAM Client and Britive SDK client
        self.iam_client = boto3.client('iam')
        self.br = Britive(tenant=os.getenv("BRITIVE_TENANT"), token=os.getenv("BRITIVE_API_TOKEN"))

    # Trust policy for SAML-based role creation
    def get_trust_policy(self):
        print(f'saml arn: "{self.saml_provider_arn}"')
        trust_policy = {
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Principal": {
                        "Federated": self.saml_provider_arn
                    },
                    "Action": [
                        "sts:AssumeRoleWithSAML",
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
        if self.sess:
            print(f'Adding invalidation')
            inv_trust = ["sts:TagSession"]
            trust_policy["Statement"][0]["Action"].extend(inv_trust)
        print(f'TrustPolicy: \n {json.dumps(trust_policy)}')
        return json.dumps(trust_policy)

    # Inline policy for the britive idp
    def get_inline_policy(self):
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
        if self.sess:
            inv_actions = [
                "iam:CreatePolicy",
                "iam:DeletePolicy",
                "iam:CreatePolicyVersion",
                "iam:DeletePolicyVersion",
                "iam:GetPolicy",
                "iam:GetPolicyVersion",
                "iam:ListPolicyVersions"
            ]
            inline_policy["Statement"][0]["Action"].extend(inv_actions)
        return json.dumps(inline_policy)

    '''
    Create a Britive as the Identity Provider for AWS IAM Role assumptions
    '''

    def create_idp(self):
        # SAML metadata document, you can load it from a file or provide directly as a string.
        # Make sure it is the SAML Metadata document from your Identity Provider.
        self.saml_metadata_document = self.br.saml.metadata()

        try:
            # Create the SAML Identity Provider
            response = self.iam_client.create_saml_provider(
                SAMLMetadataDocument=self.saml_metadata_document,
                Name=self.identity_provider_name
            )
            self.saml_provider_arn = response['SAMLProviderArn']
            # Print the response from AWS (containing the ARN of the new provider)
            print(f"{self.info}Identity Provider ARN: {self.saml_provider_arn}{Style.RESET_ALL}")
        except Exception as e:
            print(f"{self.caution}Error creating Identity Provider: {e}{Style.RESET_ALL}")

    '''
    Create a Role that will be attached to the Britive Identity Provider
    '''

    def create_role(self):
        # Create the IAM Role
        try:
            create_role_response = self.iam_client.create_role(
                RoleName=self.role_name,
                AssumeRolePolicyDocument=self.get_trust_policy(),
                Description=self.role_description,
                MaxSessionDuration=3600  # Set max session duration to 1 hour
            )
            print(f"{self.info}Role created successfully: {create_role_response['Role']['Arn']}{Style.RESET_ALL}")
        except Exception as e:
            print(f"{self.caution}Error creating role: {e}{Style.RESET_ALL}")
            exit(1)

        # Attach the necessary managed policies
        try:
            self.iam_client.attach_role_policy(
                RoleName=self.role_name,
                PolicyArn='arn:aws:iam::aws:policy/IAMReadOnlyAccess'
            )
            self.iam_client.attach_role_policy(
                RoleName=self.role_name,
                PolicyArn='arn:aws:iam::aws:policy/AWSOrganizationsReadOnlyAccess'
            )
            print(
                f'{self.info}Attached IAMReadOnlyAccess and AWSOrganizationsReadOnlyAccess policies.{Style.RESET_ALL}')
        except Exception as e:
            print(f'{self.caution}Error attaching policies: {e}{Style.RESET_ALL}')
            exit(1)

        # Add the inline policy for Britive-managed roles support
        try:
            self.iam_client.put_role_policy(
                RoleName=self.role_name,
                PolicyName='BritiveManagedRolesSupport',
                PolicyDocument=self.get_inline_policy()
            )
            print(f'{self.info}Added inline policy for Britive-managed roles support.{Style.RESET_ALL}')
        except Exception as e:
            print(f'Error adding inline policy: {e}{Style.RESET_ALL}')
            exit(1)

        print(f'{self.info}Role {self.role_name} setup complete.{Style.RESET_ALL}')


if __name__ == "__main__":
    # Define arguments and usage
    parser = argparse.ArgumentParser(description='Process some command-line arguments.')
    parser.add_argument('-i', '--idp', action='store_true',
                        help='Create Britive as an Identity Provider', default=False)
    parser.add_argument('-r', '--role', action='store_true',
                        help='Create Britive Integration Role', default=False)
    parser.add_argument('-s', '--session', action='store_true',
                        help='Setup for session invalidation', default=False)
    parser.add_argument('-m', '--managed', action='store_true',
                        help='Setup Britive managed policies', default=False)
    args = parser.parse_args()

    # Instantiate the class
    aws_int = BritiveInt(sess=args.session, managed=args.managed)
    if args.idp:
        aws_int.create_idp()
    if args.role:
        aws_int.create_role()

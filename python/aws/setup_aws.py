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

client = boto3.client('iam')


def create_role():
    # Initialize the IAM client
    iam_client = boto3.client('iam')
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

    # Create the IAM Role
    try:
        create_role_response = iam_client.create_role(
            RoleName=role_name,
            AssumeRolePolicyDocument=json.dumps(trust_policy),
            Description=role_description,
            MaxSessionDuration=3600  # Set max session duration to 1 hour
        )
        print(f"Role created successfully: {create_role_response['Role']['Arn']}")
    except Exception as e:
        print(f"Error creating role: {e}")
        exit(1)

    # Attach the necessary managed policies
    try:
        iam_client.attach_role_policy(
            RoleName=role_name,
            PolicyArn='arn:aws:iam::aws:policy/IAMReadOnlyAccess'
        )
        iam_client.attach_role_policy(
            RoleName=role_name,
            PolicyArn='arn:aws:iam::aws:policy/AWSOrganizationsReadOnlyAccess'
        )
        print("Attached IAMReadOnlyAccess and AWSOrganizationsReadOnlyAccess policies.")
    except Exception as e:
        print(f"Error attaching policies: {e}")
        exit(1)

    # Add the inline policy for Britive-managed roles support
    try:
        iam_client.put_role_policy(
            RoleName=role_name,
            PolicyName='BritiveManagedRolesSupport',
            PolicyDocument=json.dumps(inline_policy)
        )
        print("Added inline policy for Britive-managed roles support.")
    except Exception as e:
        print(f"Error adding inline policy: {e}")
        exit(1)

    print(f"Role {role_name} setup complete.")


def main():
    parser = argparse.ArgumentParser(description='Process some command-line arguments.')
    parser.add_argument('-i', '--idps', action='store_true', help='Create Britive as an Identity Provider')
    parser.add_argument('-r', '--users', action='store_true', help='Create Britive Integration Role')


if __name__ == '__main__':
    main()

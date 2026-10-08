#!/usr/bin/env python3
"""Create the AWS side of a Britive integration: the SAML identity provider
and the integration role, with the optional session-invalidation and Access
Builder permissions.

The same resources the CloudFormation and Terraform templates in this
repository create; use this when you want them from a script.

Environment (or .env next to this file):
    BRITIVE_TENANT      tenant subdomain, e.g. acme
    BRITIVE_API_TOKEN   Britive API token (reads the tenant's SAML metadata)
AWS credentials come from the usual boto3 sources (AWS_PROFILE, env, SSO).

Matches docs.britive.com/docs/configuring-identity-provider,
configuring-iam-roles and configuring-for-session-invalidation.
"""

import argparse
import json
import os
import sys
from pathlib import Path

import boto3
from botocore.exceptions import ClientError
from dotenv import load_dotenv

from britive.britive import Britive

SAML_AUDIENCE = "https://signin.aws.amazon.com/saml"


class BritiveAwsIntegration:
    def __init__(self, tenant: str, token: str, idp_name: str, role_name: str,
                 max_session_duration: int, invalidation: bool, access_builder: bool,
                 ai_scanning: bool):
        self.tenant = tenant
        self.idp_name = idp_name
        self.role_name = role_name
        self.max_session_duration = max_session_duration
        self.invalidation = invalidation
        self.access_builder = access_builder
        self.ai_scanning = ai_scanning

        self.iam = boto3.client("iam")
        sts = boto3.client("sts")
        identity = sts.get_caller_identity()
        self.account_id = identity["Account"]
        self.partition = identity["Arn"].split(":")[1]
        self.britive = Britive(tenant=tenant, token=token)

    # -- identity provider -------------------------------------------------

    def saml_provider_arn(self) -> str | None:
        """ARN of the provider named idp_name if it already exists."""
        for provider in self.iam.list_saml_providers()["SAMLProviderList"]:
            if provider["Arn"].rsplit("/", 1)[-1] == self.idp_name:
                return provider["Arn"]
        return None

    def create_idp(self) -> str:
        existing = self.saml_provider_arn()
        if existing:
            print(f"SAML provider {self.idp_name} already exists: {existing}")
            return existing
        metadata = self.britive.security.saml.metadata()
        response = self.iam.create_saml_provider(Name=self.idp_name, SAMLMetadataDocument=metadata)
        arn = response["SAMLProviderArn"]
        print(f"Created SAML provider {self.idp_name}: {arn}")
        return arn

    # -- integration role --------------------------------------------------

    def trust_policy(self, provider_arn: str) -> str:
        # Every role Britive brokers needs these three actions; SetSourceIdentity
        # once a Source Identity attribute is configured, TagSession for
        # session invalidation.
        return json.dumps({
            "Version": "2012-10-17",
            "Statement": [{
                "Effect": "Allow",
                "Principal": {"Federated": provider_arn},
                "Action": ["sts:AssumeRoleWithSAML", "sts:SetSourceIdentity", "sts:TagSession"],
                "Condition": {"StringEquals": {"SAML:aud": SAML_AUDIENCE}},
            }],
        })

    def invalidation_policy(self) -> str:
        return json.dumps({
            "Version": "2012-10-17",
            "Statement": [{
                "Effect": "Allow",
                "Action": [
                    "iam:CreatePolicy", "iam:DeletePolicy", "iam:CreatePolicyVersion",
                    "iam:DeletePolicyVersion", "iam:GetPolicy", "iam:GetPolicyVersion",
                    "iam:ListPolicyVersions",
                ],
                "Resource": f"arn:{self.partition}:iam::{self.account_id}:policy/britive/managed/*",
            }],
        })

    def access_builder_policy(self) -> str:
        return json.dumps({
            "Version": "2012-10-17",
            "Statement": [{
                "Effect": "Allow",
                "Action": [
                    "iam:CreateRole", "iam:DeleteRole", "iam:UpdateRole", "iam:TagRole",
                    "iam:UntagRole", "iam:AttachRolePolicy", "iam:DetachRolePolicy",
                    "iam:PutRolePolicy", "iam:DeleteRolePolicy",
                ],
                "Resource": f"arn:{self.partition}:iam::{self.account_id}:role/britive/managed/*",
            }],
        })

    def create_role(self) -> str:
        provider_arn = self.saml_provider_arn()
        if not provider_arn:
            sys.exit(f"SAML provider {self.idp_name} does not exist; run with --idp first")

        try:
            response = self.iam.create_role(
                RoleName=self.role_name,
                AssumeRolePolicyDocument=self.trust_policy(provider_arn),
                Description="Assumed by Britive to scan this account",
                MaxSessionDuration=self.max_session_duration,
            )
            role_arn = response["Role"]["Arn"]
            print(f"Created role {self.role_name}: {role_arn}")
        except ClientError as exc:
            if exc.response["Error"]["Code"] != "EntityAlreadyExists":
                raise
            role_arn = self.iam.get_role(RoleName=self.role_name)["Role"]["Arn"]
            print(f"Role {self.role_name} already exists: {role_arn}")
            self.iam.update_assume_role_policy(RoleName=self.role_name, PolicyDocument=self.trust_policy(provider_arn))

        managed = ["IAMReadOnlyAccess", "AWSOrganizationsReadOnlyAccess"]
        if self.ai_scanning:
            managed.append("AmazonBedrockReadOnly")
        for policy in managed:
            self.iam.attach_role_policy(RoleName=self.role_name, PolicyArn=f"arn:{self.partition}:iam::aws:policy/{policy}")
        print(f"Attached {', '.join(managed)}")

        if self.invalidation:
            self.iam.put_role_policy(RoleName=self.role_name, PolicyName="britive-aws-invalidation",
                                     PolicyDocument=self.invalidation_policy())
            print("Added session-invalidation policy (policy/britive/managed/*)")
        if self.access_builder:
            self.iam.put_role_policy(RoleName=self.role_name, PolicyName="britive-access-builder",
                                     PolicyDocument=self.access_builder_policy())
            print("Added Access Builder policy (role/britive/managed/*)")

        print("\nBritive application fields:")
        print(f"  Account ID:                      {self.account_id}")
        print(f"  Identity Provider Name:          {self.idp_name}")
        print(f"  Integration Role Name:           {self.role_name}")
        print(f"  Duration of backend connection:  {self.max_session_duration // 3600} hour(s)")
        return role_arn


def main() -> None:
    load_dotenv(Path(__file__).with_name(".env"))
    tenant_default = os.getenv("BRITIVE_TENANT")

    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("-i", "--idp", action="store_true", help="create the SAML identity provider")
    parser.add_argument("-r", "--role", action="store_true", help="create the integration role (needs the provider)")
    parser.add_argument("--tenant", default=tenant_default, help="Britive tenant subdomain (default: BRITIVE_TENANT)")
    parser.add_argument("--idp-name", help="SAML provider name (default: britive-<tenant>)")
    parser.add_argument("--role-name", help="integration role name (default: britive-<tenant>-integration-role)")
    parser.add_argument("--max-session-duration", type=int, default=3600,
                        help="role maximum session duration in seconds, 3600-43200 (default 3600)")
    parser.add_argument("--no-invalidation", action="store_true", help="skip the session-invalidation permissions")
    parser.add_argument("-m", "--access-builder", action="store_true",
                        help="add the Access Builder permissions on role/britive/managed/*")
    parser.add_argument("--ai-scanning", action="store_true", help="attach AmazonBedrockReadOnly for AI identity scanning")
    args = parser.parse_args()

    if not args.idp and not args.role:
        parser.error("nothing to do: pass --idp and/or --role")
    if not args.tenant:
        parser.error("--tenant or BRITIVE_TENANT is required")
    token = os.getenv("BRITIVE_API_TOKEN")
    if not token:
        parser.error("BRITIVE_API_TOKEN is required (environment or .env)")
    if not 3600 <= args.max_session_duration <= 43200:
        parser.error("--max-session-duration must be between 3600 and 43200")

    integration = BritiveAwsIntegration(
        tenant=args.tenant,
        token=token,
        idp_name=args.idp_name or f"britive-{args.tenant}",
        role_name=args.role_name or f"britive-{args.tenant}-integration-role",
        max_session_duration=args.max_session_duration,
        invalidation=not args.no_invalidation,
        access_builder=args.access_builder,
        ai_scanning=args.ai_scanning,
    )
    try:
        if args.idp:
            integration.create_idp()
        if args.role:
            integration.create_role()
    except ClientError as exc:
        sys.exit(f"AWS error: {exc}")


if __name__ == "__main__":
    main()

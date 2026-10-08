#!/usr/bin/env python3
"""Create what the Britive OCI application needs in a tenancy: a service user
with an API signing key, a group, and the policy that grants the group the
four statements Britive documents for OCI 2.0
(docs.britive.com/docs/creating-a-policy-in-oracle-cloud-oci2).

Authentication: the OCI CLI configuration (~/.oci/config), as a tenancy
administrator. Tenancies with identity domains also need the user added to
the IdentityDomainAdministrator group in each domain Britive should manage;
do that in the console after running this.
"""

import argparse
import sys
from pathlib import Path

import oci

POLICY_STATEMENTS = [
    "Allow group {group} to use users in tenancy",
    "Allow group {group} to use groups in tenancy",
    "Allow group {group} to inspect policies in tenancy",
    "Allow group {group} to inspect domains in tenancy",
]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--user-name", default="britive-service", help="service user name (default britive-service)")
    parser.add_argument("--email", required=True, help="e-mail for the service user")
    parser.add_argument("--public-key-file", required=True, type=Path, help="PEM public key to upload as the user's API signing key")
    parser.add_argument("--group-name", default="BritiveGroup", help="group name (default BritiveGroup)")
    parser.add_argument("--policy-name", default="BritivePolicy", help="policy name (default BritivePolicy)")
    parser.add_argument("--config", default="~/.oci/config", help="OCI CLI config file")
    parser.add_argument("--profile", default="DEFAULT", help="profile in the config file")
    args = parser.parse_args()

    try:
        public_key = args.public_key_file.read_text(encoding="utf-8")
    except OSError as exc:
        sys.exit(f"cannot read {args.public_key_file}: {exc}")
    if "BEGIN PUBLIC KEY" not in public_key:
        sys.exit(f"{args.public_key_file} is not a PEM public key")

    config = oci.config.from_file(args.config, args.profile)
    identity = oci.identity.IdentityClient(config)
    tenancy = config["tenancy"]
    print(f"tenancy {tenancy}")

    try:
        user = identity.create_user(oci.identity.models.CreateUserDetails(
            compartment_id=tenancy, name=args.user_name, description="Britive integration service user", email=args.email,
        )).data
        print(f"created user {user.name} ({user.id})")

        api_key = identity.upload_api_key(user.id, oci.identity.models.CreateApiKeyDetails(key=public_key)).data
        print(f"uploaded API key, fingerprint {api_key.fingerprint}")

        group = identity.create_group(oci.identity.models.CreateGroupDetails(
            compartment_id=tenancy, name=args.group_name, description="Britive integration",
        )).data
        print(f"created group {group.name} ({group.id})")

        identity.add_user_to_group(oci.identity.models.AddUserToGroupDetails(user_id=user.id, group_id=group.id))
        print(f"added {user.name} to {group.name}")

        policy = identity.create_policy(oci.identity.models.CreatePolicyDetails(
            compartment_id=tenancy, name=args.policy_name, description="Britive integration",
            statements=[s.format(group=args.group_name) for s in POLICY_STATEMENTS],
        )).data
        print(f"created policy {policy.name} ({policy.id})")
    except oci.exceptions.ServiceError as exc:
        sys.exit(f"OCI error {exc.status} {exc.code}: {exc.message}")

    print("\nBritive application fields (OCI):")
    print(f"  Tenancy OCID:  {tenancy}")
    print(f"  User OCID:     {user.id}")
    print(f"  Fingerprint:   {api_key.fingerprint}")
    print("  Private key:   the key matching --public-key-file")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""List the IAM roles AWS Identity Center provisioned in this account, with
their permission set name and last-used date, into <account>.csv.

A scoping aid for migrating Identity Center permission sets to Britive
profiles: it shows which permission sets are actually used.
"""

import argparse
import csv
import sys

import boto3


def list_roles(iam, sso_region: str) -> list[dict]:
    roles = []
    params = {"PathPrefix": f"/aws-reserved/sso.amazonaws.com/{sso_region}/"}
    while True:
        response = iam.list_roles(**params)
        roles += response["Roles"]
        marker = response.get("Marker")
        if not marker:
            return roles
        params["Marker"] = marker


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--region", required=True, help="region Identity Center is enabled in, e.g. us-west-2")
    parser.add_argument("-o", "--output", help="CSV path (default <account>.csv)")
    args = parser.parse_args()

    iam = boto3.client("iam")
    account = boto3.client("sts").get_caller_identity()["Account"]

    rows = []
    for role in list_roles(iam, args.region):
        name = role["RoleName"]
        last_used = iam.get_role(RoleName=name)["Role"].get("RoleLastUsed", {}).get("LastUsedDate", "never")
        rows.append({
            "Account": account,
            "RoleName": name,
            "Arn": role["Arn"],
            "PermissionSetName": "_".join(name.split("_")[1:-1]),
            "LastUsedDate": str(last_used),
        })

    if not rows:
        sys.exit(f"no Identity Center roles found under /aws-reserved/sso.amazonaws.com/{args.region}/")

    output = args.output or f"{account}.csv"
    with open(output, "w", newline="", encoding="utf-8") as csv_file:
        writer = csv.DictWriter(csv_file, fieldnames=rows[0].keys())
        writer.writeheader()
        writer.writerows(rows)
    print(f"wrote {len(rows)} roles to {output}")


if __name__ == "__main__":
    main()

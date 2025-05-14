#!/usr/bin/env python3
import csv
import json

import boto3

iam = boto3.client("iam")
sso_region = "us-west-2"


def list_roles():
    roles = []
    params = {"PathPrefix": f"/aws-reserved/sso.amazonaws.com/{sso_region}/"}
    while True:
        response = iam.list_roles(**params)
        roles += response["Roles"]
        if marker := response.get("Marker"):
            params["Marker"] = marker
            continue
        break
    return roles


def get_role(role_name):
    return iam.get_role(RoleName=role_name)


def main():
    account = str(boto3.client("sts").get_caller_identity()["Account"])
    sso_roles = []
    for role in list_roles():
        name = role["RoleName"]
        sso_roles.append(
            {
                "Account": account,
                "RoleName": name,
                "Arn": role["Arn"],
                "PermissionSetName": "_".join(name.split("_")[1:-1]),
                "LastUsedDate": str(
                    iam.get_role(RoleName=name)["Role"]["RoleLastUsed"].get(
                        "LastUsedDate", "never"
                    )
                ),
            }
        )

    with open(f"{account}.csv", "w") as csv_file:
        csv_writer = csv.writer(csv_file)
        header = sso_roles[0].keys()
        csv_writer.writerow(header)
        for item in sso_roles:
            csv_writer.writerow(item.values())


if __name__ == "__main__":
    main()

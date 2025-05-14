#!/usr/bin/env python3
import argparse
import os

import boto3
from britive.britive import Britive
from colorama import Fore, Style
from dotenv import load_dotenv

try:
    import simplejson as json
except ImportError:
    import json

# Color definitions
caution: str = f"{Style.BRIGHT}{Fore.RED}"
warn: str = f"{Style.BRIGHT}{Fore.YELLOW}"
info: str = f"{Style.BRIGHT}{Fore.BLUE}"
green: str = f"{Style.BRIGHT}{Fore.GREEN}"

# Init AWS EKS client
client = boto3.client("eks")

# Pull input data
load_dotenv()
with open("./data_input.json", "r") as file:
    data = json.load(file)

# Init Britive client
br = Britive(tenant=os.getenv("BRITIVE_TENANT"), token=os.getenv("BRITIVE_API_TOKEN"))


def main():
    parser = argparse.ArgumentParser(description="Process some command-line arguments.")
    parser.add_argument(
        "-b",
        "--britive",
        action="store_true",
        help="Process updates to Britive from the data_input file",
    )

    for group in data["environment_groups"]:
        group_id = br.application_management.environment_groups.create(
            application_id=app_id, name=group["name"]
        )["group_id"]
        for env in group["environments"]:
            br.application_management.environments.create(
                parent_group_id=group_id,
                application_id=app_id,
                description=f"k8s Enviornment for cluster {env['name']}",
                name=env["name"],
            )

    idp_name = "britive"
    cluster_dtls = client.describe_cluster(name=cluster_name)["cluster"]
    cluster_cert = cluster_dtls["certificateAuthority"]["data"]
    cluster_endpoint = cluster_dtls["endpoint"]

    response = client.associate_identity_provider_config(
        clusterName=cluster_name,
        oidc={
            "identityProviderConfigName": idp_name,
            "issuerUrl": issuer_url,
            "clientId": client_id,
            "usernameClaim": "sub",
            "usernamePrefix": "",
            "groupsClaim": "groups",
            "groupsPrefix": "",
        },
        tags={"idp": "oidc"},
        clientRequestToken="string",
    )


if __name__ == "__main__":
    main()

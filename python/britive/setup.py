#!/usr/bin/env python3
"""
This script automates Britive tenant setup using a YAML data input file.

Features:
- Connects to Britive using credentials from a .env file
- Processes various entity types (users, apps, IDPs, tags, notifications, etc.)
- Supports --dry-run mode to preview actions without executing them

Requirements:
- .env file with BRITIVE_TENANT and BRITIVE_API_TOKEN
- YAML input file (e.g., britive/data_input.yaml)
- Required packages: britive, jmespath, pyyaml, python-dotenv, colorama
"""

import argparse
import os
import secrets
import string
import yaml
import jmespath
from colorama import Fore, Style
from dotenv import load_dotenv
from britive.britive import Britive

# Color-coded output for readability
caution = f"{Style.BRIGHT}{Fore.RED}"
warn = f"{Style.BRIGHT}{Fore.YELLOW}"
info = f"{Style.BRIGHT}{Fore.BLUE}"
green = f"{Style.BRIGHT}{Fore.GREEN}"

# Load environment variables from .env file
load_dotenv()
BRITIVE_TENANT = os.getenv("BRITIVE_TENANT")
BRITIVE_API_TOKEN = os.getenv("BRITIVE_API_TOKEN")

if not BRITIVE_TENANT or not BRITIVE_API_TOKEN:
    print(
        f"{caution}Missing BRITIVE_TENANT or BRITIVE_API_TOKEN in environment variables.{Style.RESET_ALL}"
    )
    exit(1)

# Load YAML input data
DATA_FILE_INPUT = "britive/data_input.yaml"
try:
    with open(DATA_FILE_INPUT, "r") as file:
        data = yaml.safe_load(file)
except FileNotFoundError:
    print(f"{caution}Data file '{DATA_FILE_INPUT}' not found.{Style.RESET_ALL}")
    exit(1)
except yaml.YAMLError as e:
    print(f"{caution}YAML parsing error in '{DATA_FILE_INPUT}': {e}{Style.RESET_ALL}")
    exit(1)

# Initialize Britive API session
try:
    br = Britive(tenant=BRITIVE_TENANT, token=BRITIVE_API_TOKEN)
    print(f"{info}Connected to Britive tenant: {BRITIVE_TENANT}{Style.RESET_ALL}")
except Exception as e:
    print(f"{caution}Failed to initialize Britive API: {e}{Style.RESET_ALL}")
    exit(1)

# Get ID of local Britive identity provider (used for tagging)
try:
    idp_list = br.identity_management.identity_providers.list()
    britive_idp = next(
        (item["id"] for item in idp_list if item["name"] == "Britive"), None
    )
    if not britive_idp:
        raise ValueError("Britive Identity Provider ID not found.")
except Exception as e:
    print(f"{caution}Error retrieving Britive IDP: {e}{Style.RESET_ALL}")
    exit(1)

# Will be set from --dry-run argument
DRY_RUN = False


def main():
    global DRY_RUN
    parser = argparse.ArgumentParser(description="Britive tenant bootstrap utility")
    parser.add_argument(
        "-i", "--idps", action="store_true", help="Process Identity providers"
    )
    parser.add_argument(
        "-u", "--users", action="store_true", help="Process User identities"
    )
    parser.add_argument(
        "-s", "--services", action="store_true", help="Process Service identities"
    )
    parser.add_argument("-t", "--tags", action="store_true", help="Process Tags")
    parser.add_argument(
        "-a", "--applications", action="store_true", help="Process Applications"
    )
    parser.add_argument(
        "-p",
        "--profiles",
        action="store_true",
        help="Process Profiles for each application",
    )
    parser.add_argument(
        "-n", "--notification", action="store_true", help="Process Notification Mediums"
    )
    parser.add_argument(
        "-r", "--resourceTypes", action="store_true", help="Process Resource Types"
    )
    parser.add_argument(
        "-b",
        "--brokerPool",
        action="store_true",
        help="Process creation of Broker Pool",
    )
    parser.add_argument(
        "--dry-run", action="store_true", help="Simulate operations without API calls"
    )

    args = parser.parse_args()
    DRY_RUN = args.dry_run

    try:
        if args.idps:
            process_idps()
        if args.users:
            process_users()
        if args.tags:
            process_tags()
        if args.applications:
            process_applications()
        if args.profiles:
            process_profiles()
        if args.notification:
            process_notification()
        if args.brokerPool:
            process_broker_pool()
        if args.resourceTypes:
            process_resource_types()
    except Exception as e:
        print(f"{caution}An error occurred: {e}{Style.RESET_ALL}")
        exit(1)


def process_tags():
    tags = jmespath.search("tags", data) or []
    print(f"{info}Processing {len(tags)} Tags...{Style.RESET_ALL}")
    for tag in tags:
        print(f"{tag['name']}")
        if DRY_RUN:
            print(f"{warn}[Dry-Run] Would create tag: {tag['name']}{Style.RESET_ALL}")
            tag["id"] = f"simulated-{tag['name']}-id"
        else:
            tag_response = br.identity_management.tags.create(
                name=tag["name"], description=tag["description"], idp=britive_idp
            )
            tag["id"] = tag_response["userTagId"]


def process_users():
    users = jmespath.search("users", data) or []
    print(f"{info}Processing {len(users)} Users...{Style.RESET_ALL}")
    for user in users:
        try:
            print(f"{user['email']} on {user['idp']}")
            idp_response = br.identity_management.identity_providers.get_by_name(
                user["idp"]
            )
            user_idp = idp_response["id"]

            password = "".join(
                secrets.choice(string.ascii_letters + string.digits) for _ in range(12)
            )
            print(f"{warn}[Password] {password}{Style.RESET_ALL}")

            if DRY_RUN:
                print(
                    f"{warn}[Dry-Run] Would create user: {user['email']}{Style.RESET_ALL}"
                )
                user["id"] = f"simulated-{user['username']}-id"
            else:
                response = br.identity_management.users.create(
                    idp=user_idp,
                    email=user["email"],
                    firstName=user["firstname"],
                    lastName=user["lastname"],
                    username=user["username"],
                    status="active",
                    password=password,
                )
                user["id"] = response["userId"]
        except Exception as e:
            print(f"{caution}Error creating user {user['email']}: {e}{Style.RESET_ALL}")


def process_applications():
    apps = jmespath.search("apps", data) or []
    catalog = br.application_management.applications.catalog()
    catalog_map = {app["name"]: app["catalogAppId"] for app in catalog}
    print(f"{info}Processing {len(apps)} Applications...{Style.RESET_ALL}")
    for app in apps:
        catalog_id = catalog_map.get(app["type"])
        if DRY_RUN:
            print(
                f"{warn}[Dry-Run] Would create app: {app['name']} with catalog ID: {catalog_id}{Style.RESET_ALL}"
            )
            app["id"] = f"simulated-{app['name']}-id"
        else:
            response = br.application_management.applications.create(
                application_name=app["name"], catalog_id=catalog_id
            )
            app["id"] = response["appContainerId"]


def process_profiles():
    apps = jmespath.search("apps", data) or []
    for app in apps:
        envs = app.get("envs", [])
        for env in envs:
            if DRY_RUN:
                print(
                    f"{warn}[Dry-Run] Would create environment: {env['name']} for app: {app['name']}{Style.RESET_ALL}"
                )
            else:
                br.application_management.environments.create(
                    application_id=app["id"],
                    name=env["name"],
                    description=env["description"],
                )

        profiles = app.get("profiles", [])
        for profile in profiles:
            if DRY_RUN:
                print(
                    f"{warn}[Dry-Run] Would create profile: {profile['name']} for app: {app['name']}{Style.RESET_ALL}"
                )
            else:
                br.application_management.profiles.create(
                    application_id=app["id"],
                    name=profile["name"],
                    status="active",
                    expirationDuration=profile["Expiration"],
                )


def process_notification():
    notes = jmespath.search("notification", data) or []
    for note in notes:
        if DRY_RUN:
            print(
                f"{warn}[Dry-Run] Would create notification: {note['name']}{Style.RESET_ALL}"
            )
        else:
            br.global_settings.notification_mediums.create(
                name=note["name"],
                description=note["description"],
                notification_medium_type=note["type"],
                url=note["url"],
            )


def process_idps():
    idps = jmespath.search("idps", data) or []
    print(f"{info}Processing {len(idps)} Identity Providers...{Style.RESET_ALL}")
    for idp in idps:
        if DRY_RUN:
            print(f"{warn}[Dry-Run] Would create IDP: {idp['name']}{Style.RESET_ALL}")
            idp["id"] = f"simulated-{idp['name']}-id"
        else:
            response = br.identity_management.identity_providers.create(
                name=idp["name"], description=idp["description"]
            )
            idp["id"] = response["id"]


def process_broker_pool():
    if DRY_RUN:
        print(
            f"{warn}[Dry-Run] Would create Broker Pool: Primary Pool{Style.RESET_ALL}"
        )
    else:
        response = br.access_broker.pools.create(
            name="Primary Pool", description="Broker Pool for Britive Broker"
        )
        print(f"{green}Created Broker Pool: {response['pool-id']}{Style.RESET_ALL}")


def process_resource_types():
    rts = jmespath.search("resourcesTypes", data) or []
    for rt in rts:
        if DRY_RUN:
            print(
                f"{warn}[Dry-Run] Would create resource type: {rt['name']}{Style.RESET_ALL}"
            )
            rt["id"] = f"simulated-{rt['name']}-id"
        else:
            response = br.access_broker.resources.types.create(
                name=rt["name"], description=rt.get("description", "")
            )
            rt["id"] = response["resourceTypeId"]

        perms = rt.get("permissions", [])
        for perm in perms:
            if DRY_RUN:
                print(
                    f"{warn}[Dry-Run] Would create permission: {perm['name']} under {rt['name']}{Style.RESET_ALL}"
                )
            else:
                br.access_broker.resources.permissions.create(
                    name=perm["name"],
                    resource_type_id=rt["id"],
                    description=perm["description"],
                    variables=perm["variables"],
                    checkout_file=perm["checkout"],
                    checkin_file=perm["checkin"],
                )

        resources = rt.get("resources", [])
        for resource in resources:
            if DRY_RUN:
                print(
                    f"{warn}[Dry-Run] Would create resource: {resource['name']} under {rt['name']}{Style.RESET_ALL}"
                )
            else:
                br.access_broker.resources.create(
                    name=resource["name"],
                    description=resource["description"],
                    resource_type_id=rt["id"],
                )

        profiles = rt.get("profiles", [])
        for profile in profiles:
            if DRY_RUN:
                print(
                    f"{warn}[Dry-Run] Would create profile: {profile['name']} and associate to {rt['name']}{Style.RESET_ALL}"
                )
            else:
                response = br.access_broker.profiles.create(
                    name=profile["name"],
                    description=profile["description"],
                    expiration_duration=profile["Expiration"],
                )
                br.access_broker.profiles.add_association(
                    profile_id=response["profileId"],
                    associations={"Resource-Type": rt["name"]},
                )


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
import argparse
from dotenv import load_dotenv
import os

from eks.setup_eks import caution

try:
    import simplejson as json
except ImportError:
    import json
import jmespath
from colorama import Fore, Style
from britive.britive import Britive

'''
This code requires a .env file with the information about the Britive tenant to connect to.
Please create a .env file with following key/value pairs:
BRITIVE_TENANT
BRITIVE_API_TOKEN
'''


# Load Environment Variables
load_dotenv()

# Validate required environment variables
BRITIVE_TENANT = os.getenv("BRITIVE_TENANT")
BRITIVE_API_TOKEN = os.getenv("BRITIVE_API_TOKEN")

if not BRITIVE_TENANT or not BRITIVE_API_TOKEN:
    print(f"{caution}Missing BRITIVE_TENANT or BRITIVE_API_TOKEN in environment variables.{Style.RESET_ALL}")
    exit(1)

# Load JSON data file
DATA_FILE_INPUT = "britive/data_input.json"

try:
    with open(DATA_FILE_INPUT, "r") as file:
        data = json.load(file)
except FileNotFoundError:
    print(f"{caution}Data file '{DATA_FILE_INPUT}' not found. Ensure it exists.{Style.RESET_ALL}")
    exit(1)
except json.JSONDecodeError:
    print(f"{caution}Error decoding JSON in file '{DATA_FILE_INPUT}'. Check for syntax errors.{Style.RESET_ALL}")
    exit(1)

try:
    br = Britive(tenant=BRITIVE_TENANT, token=BRITIVE_API_TOKEN)
except Exception as e:
    print(f"{caution}Failed to initialize Britive API: {e}{Style.RESET_ALL}")
    exit(1)

# Get the id for the local (Britive) Identity Provider
try:
    idp_list = br.identity_management.identity_providers.list()
    britive_idp = next((item["id"] for item in idp_list if item["name"] == "Britive"), None)
    if not britive_idp:
        raise ValueError(f"Britive Identity Provider ID not found.")
except Exception as e:
    print(f"{caution}Error retrieving Britive IDP: {e}{Style.RESET_ALL}")
    exit(1)

# Color definitions
caution = f"{Style.BRIGHT}{Fore.RED}"
warn = f"{Style.BRIGHT}{Fore.YELLOW}"
info = f"{Style.BRIGHT}{Fore.BLUE}"
green = f"{Style.BRIGHT}{Fore.GREEN}"


def main():
    # The argument parser
    parser = argparse.ArgumentParser(description='Process some command-line arguments.')
    parser.add_argument('-i', '--idps', action='store_true', help='Process Identity providers')
    parser.add_argument('-u', '--users', action='store_true', help='Process User identities')
    parser.add_argument('-s', '--services', action='store_true', help='Process Service identities')
    parser.add_argument('-t', '--tags', action='store_true', help='Process Tags')
    parser.add_argument('-a', '--applications', action='store_true', help='Process Applications')
    parser.add_argument('-p', '--profiles', action='store_true', help='Process Profiles for each application')
    parser.add_argument('-n', '--notification', action='store_true', help='Process Notification Medium')
    parser.add_argument('-r', '--resourceTypes', action='store_true', help='Process creation of Resource Types')
    parser.add_argument('-b', '--brokerPool', action='store_true', help='Process creation of a single broker pool')

    args = parser.parse_args()

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
        print(f"{caution}An error occurred while processing: {e}{Style.RESET_ALL}")
        exit(1)

    # Save updated data back to JSON
    try:
        with open(DATA_FILE_INPUT, "w") as f:
            json.dump(data, f)
    except Exception as e:
        print(f"{caution}Failed to save updates to '{DATA_FILE_INPUT}': {e}{Style.RESET_ALL}")


def process_tags():
    tags = jmespath.search("tags", data)
    print(f'{info}Processing {len(tags)} Tags...{Style.RESET_ALL}')
    for tag in tags:
        print(f"{tag['name']}")
        tag_response = br.identity_management.tags.create(name=tag['name'], description=tag['description'],
                                                          idp=britive_idp)
        tag['id'] = tag_response['userTagId']


def process_users():
    users = jmespath.search("users", data)
    print(f'{info}Processing {len(users)} users...{Style.RESET_ALL}')
    for user in users:
        print(f"{user['email']} on {user['idp']}")
        user_idp = br.identity_management.identity_providers.get_by_name(identity_provider_name=user['idp'])['id']
        user_response = br.identity_management.users.create(idp=user_idp, email=user['email'], firstName=user['firstname'],
                                                            lastName=user['lastname'], username=user['username'], status='active')
        user['id'] = user_response['userId']


def process_applications():
    app_catalog = jmespath.search("[].{name: name, id: catalogAppId}", br.application_management.applications.catalog())
    apps = jmespath.search(expression="apps", data=data)
    print(f'{info}Processing {len(apps)} applications...{Style.RESET_ALL}')
    for app in apps:
        catalog_id = [item['id'] for item in app_catalog if item['name'] == app['type']][0]
        app_response = br.application_management.applications.create(application_name=app['name'], catalog_id=catalog_id)
        app['id'] = app_response['appContainerId']


def process_profiles():
    apps = jmespath.search(expression="apps", data=data)
    for app in apps:
        envs = app["envs"]
        print(f'{info}Processing Environments for app: {app['name']} {Style.RESET_ALL}')
        for env in envs:
            br.application_management.environments.create(application_id=app['id'], name=env['name'], description=env['description'])

        # Process Profiles after environments are created
        profiles = app["profiles"]
        print(f'{info}Processing profiles for app: {app['name']} {Style.RESET_ALL}')
        for profile in profiles:
            br.application_management.profiles.create(application_id=app['id'], name=profile['name'], status="active",
                                                      expirationDuration=profile['Expiration'])


def process_notification():
    notifications = jmespath.search(expression='notification', data=data)
    print(f'{green}Processing {len(notifications)} Notification Mediums...{Style.RESET_ALL}')
    for note in notifications:
        print(note['name'])
        br.global_settings.notification_mediums.create(name=note['name'], description=note['description'],
                                                       notification_medium_type=note['type'], url=note['url'])


def process_idps():
    idps = jmespath.search(expression="idps", data=data)
    print(f'{green}Processing {len(idps)} identity providers...{Style.RESET_ALL}')
    for idp in idps:
        idp_response = (br.identity_management.identity_providers.create(name=idp['name'], description=idp['description']))
        idp['id'] = idp_response['id']
        idp['ssoConfig'] = idp_response['ssoConfig']
        if idp['type'].lower() == "azure":
            br.identity_management.identity_providers.update(identity_provider_id=idp_response['id'], sso_provider="Azure")


def process_broker_pool():
    broker_pool = br.access_broker.pools.create(name='Primary Pool', description='Broker Pool for Britive Broker')
    print(f'{green}Create Broker Pool id: {broker_pool['pool-id']}{Style.RESET_ALL}')


def process_resource_types():
    try:
        rts = jmespath.search(expression="resourcesTypes", data=data)
        if not rts:
            print(f'{warn}No Resource Types found in the data.{Style.RESET_ALL}')
            return

        for rt in rts:
            try:
                rt_response = br.access_broker.resources.types.create(name=rt['name'], description=rt.get('description', ''))
                rt['id'] = rt_response['resourceTypeId']
                print(f'{green}Created Resource-Type: {rt["name"]} with id:{rt["id"]} {Style.RESET_ALL}')
            except Exception as e:
                print(f'{caution}Error creating Resource-Type {rt["name"]}: {e}{Style.RESET_ALL}')
                exit(1)  # Skip to the next resource type

            # Process Permissions
            try:
                perms = jmespath.search(expression="permissions", data=rt) or []
                print(f'{info}Creating Permissions {len(perms)} : {perms}{Style.RESET_ALL}')
                for perm in perms:
                    try:
                        perm_response = br.access_broker.resources.permissions.create(
                            name=perm['name'],
                            resource_type_id=rt['id'],
                            description=perm['description'],
                            variables=perm["variables"],
                            checkout_file=perm["checkout"],
                            checkin_file=perm["checkin"]
                        )
                        perm['id'] = perm_response["permissionId"]
                    except Exception as e:
                        print(f'{caution}Error creating Permission {perm["name"]}: {e}{Style.RESET_ALL}')
            except Exception as e:
                print(f'{caution}Error processing permissions for {rt["name"]}: {e}{Style.RESET_ALL}')

            # Process Resources
            try:
                resources = jmespath.search(expression="resources", data=rt) or []
                for resource in resources:
                    try:
                        resource_response = br.access_broker.resources.create(
                            name=resource['name'],
                            description=resource['description'],
                            resource_type_id=rt['id']
                        )
                        resource['id'] = resource_response['resourceId']
                        print(f'{green}Created Resource: {resource["name"]} with id: {resource["id"]}{Style.RESET_ALL}')
                    except Exception as e:
                        print(f'{caution}Error creating Resource {resource["name"]}: {e}{Style.RESET_ALL}')
            except Exception as e:
                print(f'{caution}Error processing resources for {rt["name"]}: {e}{Style.RESET_ALL}')

            # Process Profiles
            try:
                profiles = jmespath.search(expression="profiles", data=rt) or []
                for profile in profiles:
                    try:
                        profile_response = br.access_broker.profiles.create(
                            name=profile['name'],
                            description=profile['description'],
                            expiration_duration=profile['Expiration']
                        )
                        profile['id'] = profile_response['profileId']
                        print(f'{green}Created Profile: {profile["name"]} with id: {profile["id"]}{Style.RESET_ALL}')

                        assoc = {"Resource-Type": rt['name']}
                        br.access_broker.profiles.add_association(profile_id=profile['id'], associations=assoc)
                    except Exception as e:
                        print(f'{caution}Error creating Profile {profile["name"]}: {e}{Style.RESET_ALL}')
            except Exception as e:
                print(f'{caution}Error processing profiles for {rt["name"]}: {e}{Style.RESET_ALL}')

    except Exception as e:
        print(f'{caution}Unexpected error in process_resource_types: {e}{Style.RESET_ALL}')


# Press the green button in the gutter to run the script.
if __name__ == '__main__':
    main()

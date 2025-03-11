#!/usr/bin/env python3
import argparse
from dotenv import load_dotenv
import os

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

# Load data and ENVs
data_file_input = 'britive/data_input.json'

load_dotenv()
with open(data_file_input, 'r') as file:
    data = json.load(file)

br = Britive(tenant=os.getenv("BRITIVE_TENANT"), token=os.getenv("BRITIVE_API_TOKEN"))

# Get the id for the local (Britive) Identity provider. This is needed to create Users and Tags local to Britive.
idp_list = br.identity_providers.list()
britive_idp = [item['id'] for item in idp_list if item['name'] == 'Britive'][0]

# Color definitions
caution: str = f'{Style.BRIGHT}{Fore.RED}'
warn: str = f'{Style.BRIGHT}{Fore.YELLOW}'
info: str = f'{Style.BRIGHT}{Fore.BLUE}'
green: str = f'{Style.BRIGHT}{Fore.GREEN}'


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
    if args.resourceTypes:
        process_resource_types()
    if args.brokerPool:
        process_broker_pool()

    # Dump updates and changes to data to a json file
    with open(data_file_input, 'w') as f:
        json.dump(data, f)


def process_tags():
    tags = jmespath.search("tags", data)
    print(f'{info}Processing {len(tags)} Tags...{Style.RESET_ALL}')
    for tag in tags:
        print(f"{tag['name']}")
        tag_response = br.tags.create(name=tag['name'], description=tag['description'], idp=britive_idp)
        tag['id'] = tag_response['userTagId']


def process_users():
    users = jmespath.search("users", data)
    print(f'{info}Processing {len(users)} users...{Style.RESET_ALL}')
    for user in users:
        print(f"{user['email']} on {user['idp']}")
        user_idp = br.identity_providers.get_by_name(identity_provider_name=user['idp'])['id']
        user_response = br.users.create(idp=user_idp, email=user['email'], firstName=user['firstname'],
                                        lastName=user['lastname'], username=user['username'], status='active')
        user['id'] = user_response['userId']


def process_applications():
    app_catalog = jmespath.search("[].{name: name, id: catalogAppId}", br.applications.catalog())
    apps = jmespath.search(expression="apps", data=data)
    print(f'{info}Processing {len(apps)} applications...{Style.RESET_ALL}')
    for app in apps:
        catalog_id = [item['id'] for item in app_catalog if item['name'] == app['type']][0]
        app_response = br.applications.create(application_name=app['name'], catalog_id=catalog_id)
        app['id'] = app_response['appContainerId']


def process_profiles():
    apps = jmespath.search(expression="apps", data=data)
    for app in apps:
        envs = app["envs"]
        print(f'{info}Processing Environments for app: {app['name']} {Style.RESET_ALL}')
        for env in envs:
            br.environments.create(application_id=app['id'], name=env['name'], description=env['description'])

        # Process Profiles after environments are created
        profiles = app["profiles"]
        print(f'{info}Processing profiles for app: {app['name']} {Style.RESET_ALL}')
        for profile in profiles:
            br.profiles.create(application_id=app['id'], name=profile['name'], status="active",
                               expirationDuration=profile['Expiration'])


def process_notification():
    notifications = jmespath.search(expression='notification', data=data)
    print(f'{green}Processing {len(notifications)} Notification Mediums...{Style.RESET_ALL}')
    for note in notifications:
        print(note['name'])
        br.notification_mediums.create(name=note['name'], description=note['description'],
                                       notification_medium_type=note['type'], url=note['url'])


def process_idps():
    idps = jmespath.search(expression="idps", data=data)
    print(f'{green}Processing {len(idps)} identity providers...{Style.RESET_ALL}')
    for idp in idps:
        idp_response = (br.identity_providers.create(name=idp['name'], description=idp['description']))
        idp['id'] = idp_response['id']
        idp['ssoConfig'] = idp_response['ssoConfig']
        if idp['type'].lower() == "azure":
            br.identity_providers.update(identity_provider_id=idp_response['id'], sso_provider="Azure")


def process_broker_pool():
    broker_pool = br.access_broker.pools.create(name='Primary Pool', description='Broker Pool for Britive Broker')
    print(f'Create Broker Pool id: {broker_pool['poolId']}')


def process_resource_types():
    rts = jmespath.search(expression="resources", data=data)
    for rt in rts:
        rt_response = br.access_broker.resources.types.create(name=rt['name'], description=rt.get('description', ''))
        rt['id'] = rt_response['resourceTypeId']
        # Process Permissions - create permissions listed
        perms = jmespath.search(expression="permissions", data=rt)
        print(f'Creating Permissions {len(perms)} : {perms}')
        for perm in perms:
            perm_response = br.access_broker.resources.permissions.create(name=perm['name'], resource_type_id=rt['id'],
                                                                          description=perm['description'],
                                                                          variables=perm["variables"],
                                                                          checkout_file=perm["checkout"], checkin_file=perm["checkin"])
            perm['id'] = perm_response["permissionId"]
        # Process profiles - create profiles for the resource type
        profiles = jmespath.search(expression="profiles", data=rt)
        for profile in profiles:
            profile_response = br.access_broker.profiles.create(name=profile[''], description=profile[''],
                                                                expiration_duration=profile[''])
            profile['id'] = profile_response['profileId']
        br.access_broker.pools.create(name='', description='')


# Press the green button in the gutter to run the script.
if __name__ == '__main__':
    main()

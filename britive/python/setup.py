#!/usr/bin/env python3
import argparse
from dotenv import load_dotenv
import os

try:
    import simplejson as json
except ImportError:
    import json
import jmespath
from colored import Fore, Back, Style
from britive.britive import Britive

'''
This code requires a .env file with the information about the Britive tenant to connect to.
Please create a .env file with following key/value pairs:
BRITIVE_TENANT
BRITIVE_API_TOKEN
'''

# Load data and ENVs
load_dotenv()
with open('./data_input.json', 'r') as file:
    data = json.load(file)

br = Britive(tenant=os.getenv("BRITIVE_TENANT"), token=os.getenv("BRITIVE_API_TOKEN"))

# Get the id for the local (Britive) Identity provider. This is needed to create Users and Tags local to Britive.
idp_list = br.identity_providers.list()
britive_idp = [item['id'] for item in idp_list if item['name'] == 'Britive'][0]

# Color definitions
caution: str = f'{Style.BOLD}{Fore.red}'
warn: str = f'{Style.BOLD}{Fore.yellow}'
info: str = f'{Style.BOLD}{Fore.blue}'
green: str = f'{Style.BOLD}{Fore.green}'


def main():
    # The argument parser
    parser = argparse.ArgumentParser(description='Process some command-line arguments.')
    parser.add_argument('-u', '--users', action='store_true', help='Process Users')
    parser.add_argument('-t', '--tags', action='store_true', help='Process Tags')
    parser.add_argument('-a', '--applications', action='store_true', help='Process Applications')
    parser.add_argument('-i', '--idps', action='store_true', help='Process Identity providers')
    args = parser.parse_args()
    print(f'{"Processing users" if args.users else "Will not process users"}')
    if args.users:
        process_users()
    if args.tags:
        process_tags()
    if args.applications:
        process_applications()
    if args.idps:
        process_idps()

    # Dump updates and changes to data to a json file
    with open('./data_out.json', 'w') as f:
        json.dump(data, f)


def process_tags():
    tags = jmespath.search("tags", data)
    for tag in tags:
        print(f"{tag['name']}")
        tag_response = br.tags.create(name=tag['name'], description=tag['description'], idp=britive_idp)
        tag['id'] = tag_response['userTagId']


def process_users():
    users = jmespath.search("users", data)
    for user in users:
        print(f"{user['email']}")
        user_response = br.users.create(idp=britive_idp, email=user['email'], firstName=user['firstname'],
                                        lastName=user['lastname'], username=user['username'], status='active')
        user['id'] = user_response['userId']


def process_applications():
    app_catalog = jmespath.search("[].{name: name, id: catalogAppId}", br.applications.catalog())
    apps = jmespath.search(expression="apps", data=data)
    for app in apps:
        catalog_id = [item['id'] for item in app_catalog if item['name'] == app['type']][0]
        app_response = br.applications.create(application_name=app['name'], catalog_id=catalog_id)
        app['id'] = app_response['appContainerId']


def process_idps():
    idps = jmespath.search(expression="idps", data=data)
    for idp in idps:
        idp_id = (br.identity_providers.create(name=idp['name'], description=idp['description']))['id']
        idp['id'] = idp_id


# Press the green button in the gutter to run the script.
if __name__ == '__main__':
    main()

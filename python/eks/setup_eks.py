#!/usr/bin/env python3
import boto3
import argparse
from dotenv import load_dotenv
import os
from colored import Fore, Style
from britive.britive import Britive

try:
    import simplejson as json
except ImportError:
    import json

# Color definitions
caution: str = f'{Style.BOLD}{Fore.red}'
warn: str = f'{Style.BOLD}{Fore.yellow}'
info: str = f'{Style.BOLD}{Fore.blue}'
green: str = f'{Style.BOLD}{Fore.green}'

# Init AWS EKS client
client = boto3.client('eks')

# Pull input data
load_dotenv()
with open('./data_input.json', 'r') as file:
    data = json.load(file)

# Init Britive client
br = Britive(tenant=os.getenv("BRITIVE_TENANT"), token=os.getenv("BRITIVE_API_TOKEN"))


def main():
    parser = argparse.ArgumentParser(description='Process some command-line arguments.')
    parser.add_argument('-b', '--britive', action='store_true', help='Process updates to Britive from the data_input file')

    cluster_name = ''
    idp_name = 'britive'
    issuer_url = ''
    client_id = ''
    cluster_dtls = client.describe_cluster(name=cluster_name)['cluster']
    cluster_cert = cluster_dtls['certificateAuthority']['data']
    cluster_endpoint = cluster_dtls['endpoint']

    response = client.associate_identity_provider_config(
        clusterName=cluster_name,
        oidc={
            'identityProviderConfigName': idp_name,
            'issuerUrl': issuer_url,
            'clientId': client_id,
            'usernameClaim': 'sub',
            'usernamePrefix': '',
            'groupsClaim': 'groups',
            'groupsPrefix': ''
        },
        tags={
            'idp': 'oidc'
        },
        clientRequestToken='string'
    )


if __name__ == '__main__':
    main()

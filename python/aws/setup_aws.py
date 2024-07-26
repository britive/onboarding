#!/usr/bin/env python3
import boto3
import os
from colored import Fore, Style
from britive.britive import Britive

try:
    import simplejson as json
except ImportError:
    import json

client = boto3.client('iam')


def main():
    response = client.create_saml_provider(
        SAMLMetadataDocument='string',
        Name='string',
        Tags=[
            {
                'Key': 'string',
                'Value': 'string'
            },
        ]
    )


if __name__ == '__main__':
    main()

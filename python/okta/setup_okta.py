import asyncio
import os
from okta.client import Client as OktaClient
from colored import Fore, Style
from britive.britive import Britive

'''
This code requires a .env file with the information about the Britive tenant to connect to.
Please create a .env file with following key/value pairs: OKTA_ORG_URL & OKTA_API_TOKEN

Alternatively, use Okta OAuth mechanism
'''

# Instantiating with a Python dictionary in the constructor
config = {
    'orgUrl': os.getenv("OKTA_ORG_URL"),
    'token': os.getenv("OKTA_API_TOKEN")
}
okta_client = OktaClient(config)

